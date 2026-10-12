import Combine
import CryptoKit
import DequeModule
import Foundation
import Observation
import OSLog
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// The default ``LogRService``: an in-memory log cache that mirrors to OSLog and, when given a
/// storage, persists every entry encrypted.
///
/// ## Pipeline
///
/// ``LogRService/log(level:message:category:file:function:line:metadata:)`` runs synchronously on the caller's
/// thread. It filters on ``LogrConfiguration/enabledLevels`` and
/// ``LogrConfiguration/categoryLevelOverrides`` (the `@autoclosure` message is never evaluated for a
/// filtered entry), renders the ``LogMessage`` with its private values in clear or redacted (see
/// ``LogrConfiguration/storesPrivateValues``), mirrors to OSLog when ``LogrConfiguration/mirrorToOSLog`` is set,
/// prepends the entry to a lock-protected deque capped at ``LogrConfiguration/maxLogEntries``, and hands it to a
/// private writer actor. The writer encrypts through ``LoggerCryptoServicing``, accumulates batches of
/// 50, or submits a partial batch after one second. Storage failures get three attempts with linear
/// backoff before the batch is dropped. Once 100,000 entries are waiting on storage the newest are shed. Every
/// dropped entry, whatever the reason, is counted in ``droppedLogCount``.
///
/// ## OSLog mirror
///
/// The mirror logs the message with every value that is not public redacted, as public text, then those values
/// as one private argument: Console shows them only while a debugger is attached or private data logging is
/// enabled. Xcode's "jump to source" for a mirrored message points into Logr, as for any wrapper around OSLog;
/// ``LogVerbosity/verbose`` appends the call site, `(File.swift:42 function())`, to find it.
///
/// ## Isolation
///
/// `init`, `log()` and the level helpers are `nonisolated`. ``recentLogs`` is `nonisolated` on `LogR`
/// itself and returns a snapshot taken under the lock, so a read right after a write sees the entry
/// from any thread; through `any LogRService` it is `@MainActor`. The observation notification is
/// dispatched to the main actor and coalesced to at most one per
/// ``LogrConfiguration/coalesceWindowMillis``. ``droppedLogCount`` and the AI results are `@MainActor`.
///
/// ## Lifecycle
///
/// Initializers never throw. The writer opens the storage and reads the key in the background, and
/// ``persistenceStatus`` is ``PersistenceStatus/opening`` until that first attempt ends. Until both can be read,
/// for example before the device's first unlock after a restart, entries wait in memory (within the
/// 100,000-entry cap) and ``persistenceStatus`` says why. Opening is retried every 30 seconds and, where UIKit
/// exists, when protected data becomes available. Once storage opens, up to `maxLogEntries` persisted entries
/// are decrypted and merged behind any entries logged since launch. A main-run-loop timer fires every
/// ``LogrConfiguration/cleanupInterval``, trims
/// entries older than ``LogrConfiguration/maxLogAge`` from memory and storage, and enforces the count
/// cap on storage; a tick that finds the previous storage pass unfinished leaves storage alone. ``flush()``
/// waits for earlier entries to finish their persistence attempts. ``clearLogs()``
/// wipes memory synchronously and clears storage in order with in-flight writes (a storage that has not opened
/// yet is cleared as soon as it opens). `deinit` finishes the
/// writer stream so buffered entries drain on a best-effort basis.
@Observable
public final class LogR: LogRService {
    /// Thread-safe backing store for ``recentLogs``, plus the coalescing guard.
    ///
    /// Mutated synchronously *under a lock* on every `log()` — from any isolation domain — so
    /// reads are always current, while the observation notification is dispatched to the main
    /// actor and coalesced (see ``scheduleObservation()``). A burst of logs therefore triggers at
    /// most one SwiftUI invalidation per `coalesceWindowMillis` window, without ever hiding a
    /// logged entry from a reader — including reads made through the `any LogRService` existential.
    private struct CacheState {
        var entries = Deque<LogEntry>()
        /// True while a coalescing window is open; guards against scheduling more than one
        /// notification task per window. Flipped under the same lock as `entries`.
        var notificationScheduled = false
        /// Bumped by ``clearLogs()``. ``mergeHistory(_:)`` merges the persisted history only while this
        /// is still `0` (no clear has happened), so history read before a clear cannot resurrect
        /// entries the clear wiped, however late it arrives.
        var generation = 0
    }

    @ObservationIgnored
    private let cache: SafeMutex<CacheState> = .init(CacheState())

    /// Thread-safe and `nonisolated`: callable from any domain. The getter records the observation
    /// dependency (`access`) and returns an O(1) copy-on-write snapshot taken under the lock.
    public nonisolated var recentLogs: LogEntries {
        access(keyPath: \.recentLogs)
        return LogEntries(cache.withLock { $0.entries })
    }

    public let configuration: LogrConfiguration

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)
    @MainActor public var privacyAnalysisResult: PrivacyAnalysisResult? {
        _privacyAnalysisResult as? PrivacyAnalysisResult
    }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)
    @MainActor public var logIssueSummary: LogIssueSummary? {
        _logIssueSummary as? LogIssueSummary
    }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)
    @MainActor public var analysisProgress: AnalysisProgress? {
        _analysisProgress as? AnalysisProgress
    }

    @MainActor public var canAnalyseLogs: Bool {
        guard #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *), let analyser else {
            return false
        }
        return analyser.isAvailable
    }

    @MainActor public private(set) var droppedLogCount: Int = 0

    @MainActor public private(set) var persistenceStatus: PersistenceStatus
    /// The writer's latest status. Each change hops to the main actor in its own task, and tasks may run out of
    /// order, so every hop publishes this value rather than the one it was created with.
    @ObservationIgnored
    private let reportedStatus = SafeMutex(PersistenceStatus.opening)
    /// Drops the writer reported that are not in ``droppedLogCount`` yet. The writer may report every shed entry
    /// on its own, so only the report that finds this at 0 hops to the main actor, and that hop takes them all.
    @ObservationIgnored
    private let unpublishedDrops = SafeMutex(0)

    /// Loggers for the common categories, precomputed once at init. Immutable, so the nonisolated
    /// logging hot path can read it without a lock; uncommon/custom categories fall back to
    /// on-demand `Logger` creation (cheap — a thin handle over `os_log_t`).
    @ObservationIgnored
    private let commonLoggers: [LogCategory: Logger]
    @ObservationIgnored
    private nonisolated(unsafe) var cleanupTimer: AnyCancellable?

    @ObservationIgnored
    private let writer: LogWriterActor?
    /// Hashes ``LogPrivacy/Mask/hash`` values for every logger without storage in this process: they have
    /// no writer to derive a key from the crypto service, and their entries never outlive the process.
    private static let processHashKey = SymmetricKey(size: .bits256)

    // Type-erased so these stored properties carry no `@available` requirement (a stored property
    // cannot be annotated `@available`, and the analyzer types are iOS 26+). The mutable result
    // stores are `@MainActor`-isolated (written only by the main-actor AI methods and read by the
    // main-actor computed properties above). The injected analyzer is an immutable `let` set once
    // at init; `LogAIAnalyzer` is `Sendable`, so it is stored as `any Sendable` and downcast back
    // in the availability-gated accessor below — keeping the class `Sendable` and `init` nonisolated.
    @MainActor private var _logIssueSummary: Any?
    @MainActor private var _privacyAnalysisResult: Any?
    @MainActor private var _analysisProgress: Any?
    private let _analyser: (any Sendable)?
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)
    private var analyser: (any LogAIAnalyzer)? {
        _analyser as? (any LogAIAnalyzer)
    }

    /// Designated initializer. `nonisolated`, so a `LogR` can be created from any isolation
    /// domain. `analyser` is type-erased to `any Sendable` because the concrete `LogAIAnalyzer`
    /// types are iOS 26+ and a stored property cannot be `@available`-gated. `retrySignals` lets tests
    /// stand in for the protected-data notification; `nil` observes it, and only when there is storage.
    init(storage: LogStorage,
         cryptoService: any LoggerCryptoServicing,
         configuration: LogrConfiguration,
         analyser: (any Sendable)?,
         retrySignals: AsyncStream<Void>?) {
        self.configuration = configuration
        _analyser = analyser
        commonLoggers = Self.makeCommonLoggers(subsystem: configuration.subsystem)
        if case .memoryOnly = storage {
            writer = nil
            _persistenceStatus = .disabled
        } else {
            writer = LogWriterActor(storage: storage, cryptoService: cryptoService, configuration: configuration,
                                    retrySignals: retrySignals ?? LogWriterActor.protectedDataAvailableSignals())
            _persistenceStatus = .opening
        }
        setup()
    }

    /// Creates a logger. Never throws: storage opens in the background, see ``persistenceStatus``.
    ///
    /// - Parameters:
    ///   - storage: Where entries persist. Defaults to ``LogStorage/memoryOnly``.
    ///   - cryptoService: Encrypts entries before they reach storage. Defaults to a ``LoggerCryptoService``
    ///     with its key in the Keychain.
    ///   - configuration: Retention, levels, verbosity and OSLog mirroring.
    public convenience init(storage: LogStorage = .memoryOnly,
                            cryptoService: any LoggerCryptoServicing = LoggerCryptoService(),
                            configuration: LogrConfiguration = .default) {
        self.init(storage: storage, cryptoService: cryptoService, configuration: configuration, analyser: nil,
                  retrySignals: nil)
    }

    /// Creates a logger that can analyse its entries. Never throws: storage opens in the background, see
    /// ``persistenceStatus``.
    ///
    /// - Parameters:
    ///   - storage: Where entries persist. Defaults to ``LogStorage/memoryOnly``.
    ///   - logAnalyser: Runs ``scanForPrivacyIssues()`` and ``summarizeIssues()``. Defaults to the on-device
    ///     ``AIAnalyzer``.
    ///   - cryptoService: Encrypts entries before they reach storage. Defaults to a ``LoggerCryptoService``
    ///     with its key in the Keychain.
    ///   - configuration: Retention, levels, verbosity and OSLog mirroring.
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)
    public convenience init(storage: LogStorage = .memoryOnly,
                            logAnalyser: any LogAIAnalyzer = AIAnalyzer(),
                            cryptoService: any LoggerCryptoServicing = LoggerCryptoService(),
                            configuration: LogrConfiguration = .default) {
        self.init(storage: storage, cryptoService: cryptoService, configuration: configuration,
                  analyser: logAnalyser, retrySignals: nil)
    }

    deinit {
        stopTimer()
        // Finishing the writer's stream lets its consumer drain and persist any buffered
        // entries, then releases it. This is best-effort; call `flush()` when you need a
        // guarantee that pending entries are persisted before termination. Any open
        // coalescing-notification task captures `self` weakly and self-cancels on dealloc.
        writer?.shutdown()
    }

    public nonisolated func record(level: LogLevel,
                                   message: @autoclosure () -> LogMessage,
                                   category: LogCategory,
                                   file: String,
                                   function: String,
                                   line: Int,
                                   metadata: [String: LogMetadataValue]?) {
        guard shouldLog(level: level, category: category) else { return }

        let message = message()
        let hashKey = message.redactions.contains { $0.kind == .hashed } ? privacyHashKey() : nil
        let stored = message.rendered(keepingPrivateValues: configuration.storesPrivateValues, hashKey: hashKey)

        let entry = LogEntry(level: level,
                             category: category,
                             subsystem: configuration.subsystem,
                             message: stored.text,
                             file: file,
                             function: function,
                             line: line,
                             metadata: metadata,
                             privateRanges: stored.privateRanges)

        if configuration.mirrorToOSLog {
            let redacted = configuration.storesPrivateValues
                ? message.rendered(keepingPrivateValues: false, hashKey: hashKey).text
                : stored.text
            mirror(message, redacted: redacted, level: level, category: category, file: file, function: function,
                   line: line)
        }

        // Append synchronously under the lock so every reader — including reads made through the
        // `any LogRService` existential, from any isolation domain — sees the entry at once. The
        // observation *notification* is dispatched to the main actor on a coalesced schedule, so a
        // burst produces a handful of SwiftUI invalidations instead of one per entry, without ever
        // hiding an entry from a reader. The `modify` returns whether this call opened the window.
        let shouldSchedule = cache.withLock { state -> Bool in
            state.entries.prepend(entry)
            while state.entries.count > configuration.maxLogEntries {
                state.entries.removeLast()
            }
            guard !state.notificationScheduled else { return false }
            state.notificationScheduled = true
            return true
        }
        if shouldSchedule {
            scheduleObservation()
        }

        // Hand the entry to the background writer. Encryption and batched persistence
        // happen inside the actor's single consumer — no per-call Task is spawned and
        // nothing accumulates on the main actor.
        writer?.ingest(entry)
    }
}

// MARK: - Coalesced observation

private extension LogR {
    /// Opens a coalescing window on the main actor: fires an immediate notification, waits
    /// `coalesceWindowMillis` (during which further logs mutate the cache silently), clears the
    /// guard, then fires once more. Called only when `log()` flipped `notificationScheduled` from
    /// false to true under the lock, so exactly one window task runs at a time. The result: at most
    /// one SwiftUI invalidation per window, no matter how fast logs arrive — the data is never
    /// withheld, only the notification is coalesced. `[weak self]` makes the task self-cancelling
    /// once the logger is released.
    nonisolated func scheduleObservation() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            notifyObservers()
            let windowMillis = max(0, configuration.coalesceWindowMillis)
            if windowMillis > 0 {
                try? await Task.sleep(for: .milliseconds(windowMillis))
            }
            // Close the window before the final notify so a log arriving afterwards reopens one.
            cache.withLock { $0.notificationScheduled = false }
            notifyObservers()
        }
    }

    /// Fires the observation for `recentLogs` without mutating it (the data was already updated
    /// synchronously under the lock in `log()`), so SwiftUI re-reads the current value.
    @MainActor
    func notifyObservers() {
        withMutation(keyPath: \.recentLogs) {}
    }
}

// MARK: - Other util functions

public extension LogR {
    func clearLogs() async throws {
        // Wipe the in-memory cache synchronously under the lock, *before* the suspension below — no
        // `log()` can interleave mid-removal. Reset the coalescing guard too; any in-flight
        // notification task is harmless (it merely re-reads the now-empty cache).
        cache.withLock { state in
            state.entries.removeAll()
            state.notificationScheduled = false
            // Supersede any in-flight startup load so it can't merge cleared entries back in.
            state.generation &+= 1
        }
        await MainActor.run { notifyObservers() }
        // Clear persisted storage *through the writer* so the clear is ordered against in-flight
        // writes: every entry ingested before this call (including any still buffered in the writer)
        // is discarded. A `log()` that races this `await` is the one ambiguous case: if its
        // `writer.ingest` lands *after* the clear marker, the entry survives in both storage and
        // `recentLogs`; if it lands *before* the marker (the in-memory wipe above has already
        // happened), the entry remains in `recentLogs` but is dropped from storage, so it won't
        // reload on next launch. Losing a single entry logged mid-clear is acceptable and the two
        // stores reconverge on relaunch. The writer exists exactly when storage does, so this fully
        // covers wiping persisted entries. (If `storage.clear()` fails the error propagates; the
        // in-memory cache is already cleared and storage reloads on next launch.)
        try await writer?.clearPending()
    }

    func flush() async {
        await writer?.flush()
    }
}

// MARK: - Logs analyzer

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)
public extension LogR {
    @MainActor
    func scanForPrivacyIssues() async throws -> PrivacyAnalysisResult {
        guard let analyser else {
            throw AIAnalyzerError.missingAnalyzer
        }

        // Single lock acquisition + O(1) COW snapshot, reused for count/isEmpty/Array below.
        let snapshot = recentLogs

        // Reset progress at start; clear it however the analysis ends, including when it throws.
        _analysisProgress = AnalysisProgress.starting(totalLogs: snapshot.count)
        defer { _analysisProgress = nil }

        let result: PrivacyAnalysisResult = if snapshot.isEmpty {
            PrivacyAnalysisResult.empty
        } else {
            try await analyser.scanForPrivacyIssues(logs: Array(snapshot)) { [weak self] progress in
                self?._analysisProgress = progress
            }
        }

        _privacyAnalysisResult = result
        return result
    }

    @MainActor
    func summarizeIssues() async throws -> LogIssueSummary {
        guard let analyser else {
            throw AIAnalyzerError.missingAnalyzer
        }

        // Single lock acquisition + O(1) COW snapshot, reused for count/isEmpty/Array below.
        let snapshot = recentLogs

        // Reset progress at start; clear it however the analysis ends, including when it throws.
        _analysisProgress = AnalysisProgress.starting(totalLogs: snapshot.count)
        defer { _analysisProgress = nil }

        let result: LogIssueSummary = if snapshot.isEmpty {
            LogIssueSummary.empty
        } else {
            try await analyser.summarizeIssues(logs: Array(snapshot)) { [weak self] progress in
                self?._analysisProgress = progress
            }
        }

        _logIssueSummary = result
        return result
    }
}

// MARK: - Cleanup helpers

extension LogR {
    /// One cleanup pass, as the timer runs it: trims expired entries from memory and asks the writer to delete
    /// expired entries and those beyond `maxLogEntries` from storage.
    @MainActor
    func performCleanup() {
        let cutoffDate = Date().addingTimeInterval(-configuration.maxLogAge)
        cache.withLock { Self.trimExpiredEntries(&$0.entries, olderThan: cutoffDate) }
        notifyObservers()
        writer?.cleanup(olderThan: cutoffDate, keepingLatest: configuration.maxLogEntries)
    }

    /// Removes entries older than `cutoff` from a newest-first deque.
    ///
    /// The cache is maintained newest-first, so expired entries always form a
    /// contiguous tail. Trimming from the back is O(number-expired) and allocates
    /// nothing when nothing has expired — unlike a full `filter`, which reallocated the
    /// entire deque on every cleanup tick. Pure (no instance state) so it is `static` and
    /// directly unit-testable.
    static func trimExpiredEntries(_ entries: inout Deque<LogEntry>, olderThan cutoff: Date) {
        while let oldest = entries.last, oldest.timestamp < cutoff {
            entries.removeLast()
        }
    }

    /// Merges history loaded from storage into the in-memory cache.
    ///
    /// `historical` arrives oldest-first (as returned by `fetchEntries(limit:)`), while
    /// `current` holds any logs captured during launch, newest-first. History is appended
    /// newest-first after those live logs, then the cache is trimmed to `cap` (dropping the
    /// oldest). This keeps the cache newest-first and never larger than `maxLogEntries`.
    /// Pure (no instance state) so it is `static` and directly unit-testable.
    static func mergeLoaded(_ historical: [LogEntry], into current: inout Deque<LogEntry>, cap: Int) {
        // The startup fetch can include live entries already persisted by the writer.
        var seen = Set(current.map(\.id))
        current.append(contentsOf: historical.reversed().filter { seen.insert($0.id).inserted })
        while current.count > cap {
            current.removeLast()
        }
    }
}

// MARK: - Setup & utils

private extension LogR {
    func setup() {
        cache.withLock { $0.entries.reserveCapacity(configuration.maxLogEntries) }

        startCleanupTimer()
        guard let writer else { return }
        Task { [weak self] in
            await writer.setOnDrop { [weak self] count in
                guard let self else { return }
                let isFirst = unpublishedDrops.withLock { unpublished -> Bool in
                    defer { unpublished += count }
                    return unpublished == 0
                }
                guard isFirst else { return }
                Task { @MainActor [weak self] in self?.publishDrops() }
            }
            await writer.setOnStatus { [weak self] status in
                self?.reportedStatus.withLock { $0 = status }
                Task { @MainActor in self?.publishReportedStatus() }
            }
        }
        Task { [weak self] in
            let history = await writer.persistedHistory()
            await self?.mergeHistory(history)
        }
    }

    @MainActor
    func publishDrops() {
        droppedLogCount += unpublishedDrops.withLock { unpublished -> Int in
            defer { unpublished = 0 }
            return unpublished
        }
    }

    @MainActor
    func publishReportedStatus() {
        let status = reportedStatus.value
        guard status != persistenceStatus else { return }
        persistenceStatus = status
    }

    /// Builds the immutable logger map for the common categories once, off the hot path.
    static func makeCommonLoggers(subsystem: String) -> [LogCategory: Logger] {
        var loggers: [LogCategory: Logger] = [:]
        loggers.reserveCapacity(LogCategory.common.count)
        for category in LogCategory.common {
            loggers[category] = Logger(subsystem: subsystem, category: category.rawValue)
        }
        return loggers
    }

    func startCleanupTimer() {
        cleanupTimer = Timer
            .publish(every: configuration.cleanupInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                // `Timer.publish(on: .main, …)` delivers on the main run loop, so it is safe to
                // assume main-actor isolation here without an extra task hop.
                MainActor.assumeIsolated { self?.performCleanup() }
            }
    }

    /// The hash key from the crypto service once the writer could read it; until then `nil`, so hashed values
    /// render as `<private>`.
    nonisolated func privacyHashKey() -> SymmetricKey? {
        guard let writer else { return Self.processHashKey }
        return writer.privacyHashKey.value
    }

    /// `OSLogMessage` cannot be built at run time and takes its privacy statically, so the message goes
    /// out through fixed templates: the redacted text as public, the values that are not public after it as
    /// private, so they show when private data is enabled or a debugger is attached.
    nonisolated func mirror(_ message: LogMessage, redacted: String, level: LogLevel, category: LogCategory,
                            file: String, function: String, line: Int) {
        let osLogger = logger(for: category)
        let type = level.osLogType
        let privateValues = message.joinedPrivateValues
        guard configuration.logVerbosity == .verbose else {
            if privateValues.isEmpty {
                osLogger.log(level: type, "\(redacted, privacy: .public)")
            } else {
                osLogger.log(level: type, "\(redacted, privacy: .public) \(privateValues, privacy: .private)")
            }
            return
        }
        let fileName = file.lastIndex(of: "/").map { file[file.index(after: $0)...] } ?? file[...]
        if privateValues.isEmpty {
            osLogger.log(level: type, """
            \(redacted, privacy: .public) (\(fileName, privacy: .public):\(line) \(function, privacy: .public))
            """)
        } else {
            osLogger.log(level: type, """
            \(redacted, privacy: .public) \(privateValues, privacy: .private) \
            (\(fileName, privacy: .public):\(line) \(function, privacy: .public))
            """)
        }
    }

    /// Returns the cached logger for a common category, or creates one on demand for uncommon /
    /// custom categories. `nonisolated` and lock-free: `commonLoggers` is immutable and `Logger`
    /// is a cheap, `Sendable` handle.
    nonisolated func logger(for category: LogCategory) -> Logger {
        commonLoggers[category] ?? Logger(subsystem: configuration.subsystem, category: category.rawValue)
    }

    nonisolated func stopTimer() {
        cleanupTimer?.cancel()
        cleanupTimer = nil
    }

    nonisolated func shouldLog(level: LogLevel, category: LogCategory) -> Bool {
        // Check category-specific minimum level override first
        if let minLevel = configuration.categoryLevelOverrides?[category] {
            return level.priority >= minLevel.priority
        }
        // Fall back to global enabled levels
        return configuration.enabledLevels.contains(level)
    }
}

// MARK: - Local storage

private extension LogR {
    /// Merges the history the writer read when storage opened, which may be long after launch.
    func mergeHistory(_ history: [LogEntry]) async {
        guard !history.isEmpty else { return }
        let didMerge = cache.withLock { state -> Bool in
            // Merge persisted history only if no `clearLogs()` has run since init. `generation`
            // starts at 0 and is bumped only by `clearLogs()`; checking it here (under the same
            // lock as the wipe) keeps a load that finishes after a clear from resurrecting entries.
            guard state.generation == 0 else { return false }
            Self.mergeLoaded(history, into: &state.entries, cap: configuration.maxLogEntries)
            return true
        }
        if didMerge {
            await MainActor.run { notifyObservers() }
        }
    }
}

// MARK: - Background Writer Actor

/// Background actor that opens the storage, then encrypts and persists log entries.
///
/// Plaintext entries are handed in synchronously via ``ingest(_:)`` and delivered to a single consumer over an
/// `AsyncStream`, so callers never spawn a per-log task and entries are persisted in the order they were logged.
/// The consumer first opens the storage, reads the persisted history and checks that the encryption key can be
/// read. Until all three succeed, entries wait as plaintext in `pending`; a failed attempt is retried every
/// `retryInterval` and whenever `retrySignals` fires (protected data becoming available).
///
/// ## Backpressure
///
/// Entries accepted by ``ingest(_:)`` and not yet encrypted, whether still in the stream or waiting in `pending`,
/// are capped at `maxPendingWrites`. Past it the *newest* entries are shed (the oldest, likely the cause being
/// diagnosed, are kept) and counted. Shed counts are reported through the same `onDrop` callback as
/// encryption/retry failures. Only entries count: control signals are never dropped, so `flush()` cannot hang.
actor LogWriterActor {
    /// Events delivered to the single consumer.
    private enum Event {
        case entry(LogEntry)
        case deadline(UUID)
        case retry
        case flush(CheckedContinuation<Void, Never>)
        /// Discards any not-yet-persisted entries buffered ahead of this signal and clears storage.
        /// Routed through the same stream as `entry`, so it is ordered *after* every entry ingested
        /// before the `clear()` call (those are dropped) and *before* any ingested after it.
        case clear(CheckedContinuation<Void, any Error>)
        case history(CheckedContinuation<[LogEntry], Never>)
        case cleanup(olderThan: Date, keepingLatest: Int)
        /// Entries were shed; while nothing is written, no entry reaches the consumer to report them.
        case reportDrops
    }

    /// Mutex-guarded backpressure state, shared between the nonisolated `ingest` producer and the
    /// actor-isolated consumer. `inFlight` counts entries accepted but not yet encrypted, dropped or cleared;
    /// `pendingDrops` accumulates shed entries until the consumer can report them via `onDrop`.
    /// `reportQueued` keeps at most one ``Event/reportDrops`` in the stream, so shedding never grows it.
    private struct Backlog {
        var inFlight = 0
        var pendingDrops = 0
        var reportQueued = false
    }

    private let storageOption: LogStorage
    private let cryptoService: any LoggerCryptoServicing
    private let logger: Logger
    private let historyLimit: Int
    private let batchSize: Int
    private let maxRetries: Int
    private let maxPendingWrites: Int
    private let partialBatchDeadline: Duration
    private let retryInterval: Duration
    private let continuation: AsyncStream<Event>.Continuation
    /// `let` of a `Sendable` type, so the nonisolated producer can touch it without hopping actors.
    private let backlog: SafeMutex<Backlog> = .init(Backlog())
    /// A cleanup pass is waiting or running; later requests are skipped until it ends, so passes slower than the
    /// cleanup timer cannot pile up ahead of writes.
    private let cleanupQueued = SafeMutex(false)
    private let retrySignalForwarding: Task<Void, Never>
    /// Read by ``LogR`` on its logging path; set once the key can be read.
    let privacyHashKey = SafeMutex<SymmetricKey?>(nil)
    /// The crypto service answered: with a key, or with `nil` or an error other than the locked Keychain.
    private var isPrivacyHashKeyResolved = false

    private var storage: (any LogRPersistence)?
    /// The persisted entries, read once when storage opens and kept until ``persistedHistory()`` takes them.
    private var history: [LogEntry]?
    private var historyWaiters: [CheckedContinuation<[LogEntry], Never>] = []
    /// A clear that arrived before storage could be opened; done as soon as it is.
    private var clearOnOpen = false
    /// Storage is open, history read, and the key could be read at the last attempt.
    private var isWriting = false
    /// Entries not encrypted yet, oldest first.
    private var pending = Deque<LogEntry>()
    private var batch: [EncryptedLogEntry] = []
    private var status = PersistenceStatus.opening
    private var onStatus: (@Sendable (PersistenceStatus) -> Void)?
    private var onDrop: (@Sendable (Int) -> Void)?
    /// Drops counted while no `onDrop` handler was registered yet; delivered by ``setOnDrop(_:)``.
    private var undeliveredDrops = 0
    private var flushTask: Task<Void, Never>?
    private var flushDeadline: UUID?
    private var retryTask: Task<Void, Never>?

    init(storage: LogStorage,
         cryptoService: any LoggerCryptoServicing,
         configuration: LogrConfiguration,
         batchSize: Int = 50,
         maxRetries: Int = 3,
         maxPendingWrites: Int = 100_000,
         partialBatchDeadline: Duration = .seconds(1),
         retryInterval: Duration = .seconds(30),
         retrySignals: AsyncStream<Void> = LogWriterActor.protectedDataAvailableSignals()) {
        storageOption = storage
        self.cryptoService = cryptoService
        historyLimit = configuration.maxLogEntries
        self.batchSize = batchSize
        self.maxRetries = maxRetries
        self.maxPendingWrites = max(1, maxPendingWrites)
        self.partialBatchDeadline = partialBatchDeadline
        self.retryInterval = retryInterval
        logger = Logger(subsystem: configuration.subsystem, category: LogCategory.persistence.rawValue)
        let (stream, continuation) = AsyncStream<Event>.makeStream()
        self.continuation = continuation
        retrySignalForwarding = Task {
            for await _ in retrySignals {
                continuation.yield(.retry)
            }
        }
        Task { await self.consume(stream) }
    }

    /// `UIApplication.protectedDataDidBecomeAvailableNotification` where UIKit has it. watchOS and macOS have no
    /// such notification and rely on the retry timer alone.
    static func protectedDataAvailableSignals() -> AsyncStream<Void> {
        #if canImport(UIKit) && !os(watchOS)
        AsyncStream { continuation in
            // Only the notification name: `UIApplication.shared` is unavailable in app extensions.
            let name = UIApplication.protectedDataDidBecomeAvailableNotification
            let task = Task {
                for await _ in NotificationCenter.default.notifications(named: name) {
                    continuation.yield()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        #else
        AsyncStream { $0.finish() }
        #endif
    }

    /// Registers a callback invoked with the number of entries dropped (encryption failures, a
    /// batch abandoned after exhausting retries, or entries shed under backpressure). Drops counted
    /// before registration are delivered immediately, so none are lost to a late handler.
    func setOnDrop(_ handler: @escaping @Sendable (Int) -> Void) {
        onDrop = handler
        reportBackpressureDrops(consumedInFlight: 0)
    }

    /// Registers a callback for persistence status changes; it is called at once with the current status.
    func setOnStatus(_ handler: @escaping @Sendable (PersistenceStatus) -> Void) {
        onStatus = handler
        handler(status)
    }

    /// Hands a plaintext entry to the writer. Synchronous and non-isolated so the main
    /// actor's logging hot path neither awaits nor spawns a task. Sheds the entry (and counts
    /// it) when the pending buffer is already at `maxPendingWrites`, so memory stays bounded.
    nonisolated func ingest(_ entry: LogEntry) {
        let cap = maxPendingWrites
        let event = backlog.withLock { state -> Event? in
            guard state.inFlight < cap else {
                state.pendingDrops += 1
                guard !state.reportQueued else { return nil }
                state.reportQueued = true
                return .reportDrops
            }
            state.inFlight += 1
            return .entry(entry)
        }
        guard let event else { return }
        continuation.yield(event)
    }

    /// Suspends until every entry enqueued before this call has been persisted, or is waiting in memory because
    /// the storage or the key cannot be read yet.
    nonisolated func flush() async {
        await withCheckedContinuation { awaiter in
            // If the stream has already finished (post-`shutdown()`), `yield` returns `.terminated`
            // and would silently drop the continuation — leaving this task suspended forever. Resume
            // immediately in that case so `flush()` can never hang.
            if case .terminated = continuation.yield(.flush(awaiter)) {
                awaiter.resume()
            }
        }
    }

    /// Discards any buffered-but-unpersisted entries enqueued before this call and clears storage,
    /// then suspends until that completes. Ordered through the stream so it never races with the
    /// consumer's in-flight writes. Throws if the underlying `storage.clear()` fails. When storage is not open
    /// yet, returns at once and clears it as soon as it opens.
    nonisolated func clearPending() async throws {
        try await withCheckedThrowingContinuation { (awaiter: CheckedContinuation<Void, Error>) in
            // Stream already finished (post-`shutdown()`): nothing left to persist or clear.
            if case .terminated = continuation.yield(.clear(awaiter)) {
                awaiter.resume()
            }
        }
    }

    /// The entries storage held when it opened (at most `maxLogEntries`, oldest first), once the writer has read
    /// them; empty when the writer shuts down first or after a clear. Meant to be called once.
    nonisolated func persistedHistory() async -> [LogEntry] {
        await withCheckedContinuation { awaiter in
            if case .terminated = continuation.yield(.history(awaiter)) {
                awaiter.resume(returning: [])
            }
        }
    }

    /// Deletes stored entries older than `cutoff`, then the oldest beyond `count`. Skipped while storage is not
    /// open, and while an earlier pass has not ended.
    nonisolated func cleanup(olderThan cutoff: Date, keepingLatest count: Int) {
        let isQueued = cleanupQueued.withLock { queued -> Bool in
            defer { queued = true }
            return queued
        }
        guard !isQueued else { return }
        continuation.yield(.cleanup(olderThan: cutoff, keepingLatest: count))
    }

    /// Ends the stream so the consumer drains its buffer and exits. Best-effort: entries still waiting for
    /// the storage or the key are lost.
    nonisolated func shutdown() {
        retrySignalForwarding.cancel()
        continuation.finish()
    }
}

private extension LogWriterActor {
    private func consume(_ stream: AsyncStream<Event>) async {
        await open()
        for await event in stream {
            switch event {
            case let .entry(entry):
                pending.append(entry)
                await drain()
            case let .deadline(id):
                guard flushDeadline == id else { continue }
                await store()
            case .retry:
                retryTask?.cancel()
                retryTask = nil
                guard !isWriting else { continue }
                await open()
            case let .flush(awaiter):
                reportBackpressureDrops(consumedInFlight: 0)
                await store()
                awaiter.resume()
            case let .clear(awaiter):
                await clear(awaiter)
            case let .history(awaiter):
                historyWaiters.append(awaiter)
                deliverHistory()
            case let .cleanup(cutoff, count):
                await deleteExpiredEntries(olderThan: cutoff, keepingLatest: count)
                cleanupQueued.withLock { $0 = false }
            case .reportDrops:
                backlog.withLock { $0.reportQueued = false }
                reportBackpressureDrops(consumedInFlight: 0)
            }
        }
        // Stream finished (shutdown): persist whatever is still buffered.
        await store()
        history = history ?? []
        deliverHistory()
        cancelDeadline()
        retryTask?.cancel()
    }

    /// Opens the storage and applies a pending clear, which need no key; then checks the key, reads the history
    /// once, and encrypts what waits in `pending`. On failure, reports why and tries again later.
    func open() async {
        resolvePrivacyHashKey()
        do {
            guard let storage = try openStorage() else { return }
            if clearOnOpen {
                try await storage.clear()
                clearOnOpen = false
            }
            try checkKey()
            // The Keychain may have unlocked since the attempt above.
            resolvePrivacyHashKey()
            if history == nil {
                history = try await readHistory(from: storage)
                deliverHistory()
            }
            isWriting = true
            setStatus(.active)
            await drain()
        } catch LoggerCryptoError.keyTemporarilyUnavailable {
            waitForRetry(.waitingForProtectedData)
        } catch {
            logger.error("Could not open log storage: \(String(describing: error))")
            waitForRetry(.failed(String(describing: error)))
        }
    }

    /// Opens the storage the first time. When that fails while the key is locked too, the lock is what says
    /// why: before the first unlock, protected files cannot be opened either.
    func openStorage() throws -> (any LogRPersistence)? {
        if let storage {
            return storage
        }
        do {
            storage = try storageOption.open()
            return storage
        } catch {
            try checkKey()
            throw error
        }
    }

    /// Hands the history, once read, to everyone waiting for it, then lets it go.
    func deliverHistory() {
        guard let history, !historyWaiters.isEmpty else { return }
        for waiter in historyWaiters {
            waiter.resume(returning: history)
        }
        historyWaiters.removeAll()
        self.history = []
    }

    /// Independent of storage, so hashing starts once the key can be read even while storage cannot open. A
    /// service without a hash key, or whose key fails for another reason, leaves hashed values as `<private>`.
    func resolvePrivacyHashKey() {
        guard !isPrivacyHashKeyResolved else { return }
        let key: SymmetricKey?
        do {
            key = try cryptoService.privacyHashKey()
        } catch LoggerCryptoError.keyTemporarilyUnavailable {
            return
        } catch {
            key = nil
        }
        isPrivacyHashKeyResolved = true
        privacyHashKey.withLock { $0 = key }
    }

    /// Throws only ``LoggerCryptoError/keyTemporarilyUnavailable``: other encryption failures surface per entry,
    /// which drops it and reports the status.
    func checkKey() throws {
        do {
            _ = try cryptoService.symmetricEncrypt(object: true)
        } catch LoggerCryptoError.keyTemporarilyUnavailable {
            throw LoggerCryptoError.keyTemporarilyUnavailable
        } catch {}
    }

    /// Throws only ``LoggerCryptoError/keyTemporarilyUnavailable``. A storage that cannot be read back still
    /// gets written to, with no history, as in Logr 1.x.
    func readHistory(from storage: any LogRPersistence) async throws -> [LogEntry] {
        let encrypted: [EncryptedLogEntry]
        do {
            encrypted = try await storage.fetchEntries(limit: historyLimit)
        } catch {
            logger.error("Could not read stored log entries: \(String(describing: error))")
            return []
        }
        var entries: [LogEntry] = []
        var decryptionFailures = 0
        for item in encrypted {
            do {
                try entries.append(cryptoService.symmetricDecrypt(encryptedData: item.data))
            } catch LoggerCryptoError.keyTemporarilyUnavailable {
                throw LoggerCryptoError.keyTemporarilyUnavailable
            } catch {
                decryptionFailures += 1
            }
        }
        if decryptionFailures > 0 {
            logger.warning("Failed to decrypt \(decryptionFailures) of \(encrypted.count) log entries")
        }
        return entries
    }

    /// Encrypts waiting entries into the batch, storing each full batch. Stops when the key cannot be read.
    func drain() async {
        guard isWriting else { return }
        while let entry = pending.first {
            let data: Data
            do {
                data = try cryptoService.symmetricEncrypt(object: entry)
            } catch LoggerCryptoError.keyTemporarilyUnavailable {
                waitForRetry(.waitingForProtectedData)
                return
            } catch {
                pending.removeFirst()
                reportBackpressureDrops(consumedInFlight: 1)
                logger.error("Failed to encrypt log entry: \(error.localizedDescription)")
                setStatus(.failed(String(describing: error)))
                reportDrops(1)
                continue
            }
            pending.removeFirst()
            reportBackpressureDrops(consumedInFlight: 1)
            batch.append(EncryptedLogEntry(id: entry.id, timestamp: entry.timestamp, data: data))
            if batch.count >= batchSize {
                await store()
            } else if flushTask == nil {
                scheduleDeadline()
            }
        }
    }

    func waitForRetry(_ reason: PersistenceStatus) {
        isWriting = false
        setStatus(reason)
        guard retryTask == nil else { return }
        let continuation = continuation
        let interval = retryInterval
        retryTask = Task { @concurrent in
            do { try await Task.sleep(for: interval) } catch { return }
            continuation.yield(.retry)
        }
    }

    func setStatus(_ newStatus: PersistenceStatus) {
        guard newStatus != status else { return }
        status = newStatus
        logger.log("Persistence status: \(String(describing: newStatus))")
        onStatus?(newStatus)
    }

    func clear(_ awaiter: CheckedContinuation<Void, any Error>) async {
        cancelDeadline()
        reportBackpressureDrops(consumedInFlight: pending.count)
        // Drop entries logged before the clear that haven't been persisted yet, then wipe
        // storage. Entries delivered *after* this event survive (they were ingested after
        // the caller asked to clear).
        pending.removeAll()
        batch.removeAll(keepingCapacity: true)
        if history != nil {
            history = []
        }
        guard let storage else {
            clearOnOpen = true
            awaiter.resume()
            return
        }
        do {
            try await storage.clear()
            awaiter.resume()
        } catch {
            awaiter.resume(throwing: error)
        }
    }

    func deleteExpiredEntries(olderThan cutoff: Date, keepingLatest count: Int) async {
        guard let storage else { return }
        do {
            try await storage.deleteEntries(olderThan: cutoff)
            if try await storage.count() > count {
                try await storage.deleteEntries(keepingLatest: count)
            }
        } catch {
            logger.error("Cleanup failed: \(error.localizedDescription)")
        }
    }

    func scheduleDeadline() {
        let id = UUID()
        flushDeadline = id
        let continuation = continuation
        let deadline = partialBatchDeadline
        // The timer only enqueues an event; persistence stays ordered with flush and clear.
        flushTask = Task { @concurrent in
            do { try await Task.sleep(for: deadline) } catch { return }
            continuation.yield(.deadline(id))
        }
    }

    func cancelDeadline() {
        flushTask?.cancel()
        flushTask = nil
        flushDeadline = nil
    }

    /// Decrements the in-flight count for entries that left the plaintext stage and forwards any entries shed
    /// under backpressure since the last report to `onDrop`, so callers can surface the loss.
    func reportBackpressureDrops(consumedInFlight: Int) {
        let dropped = backlog.withLock { state -> Int in
            state.inFlight -= consumedInFlight
            let pending = state.pendingDrops
            state.pendingDrops = 0
            return pending
        }
        if dropped > 0 {
            logger.error("Shed \(dropped) log entries under backpressure (storage fell behind)")
        }
        reportDrops(dropped)
    }

    /// The single path every drop takes to `onDrop`; holds the count until a handler exists.
    func reportDrops(_ count: Int) {
        undeliveredDrops += count
        guard undeliveredDrops > 0, let onDrop else { return }
        onDrop(undeliveredDrops)
        undeliveredDrops = 0
    }

    /// Stores the batch, retrying with linear backoff. Entries are cleared only after a
    /// successful write, so a transient failure never loses data. After `maxRetries`
    /// failures the batch is dropped (and reported via `onDrop`) so the loop can't stall.
    func store() async {
        cancelDeadline()
        guard !batch.isEmpty, let storage else { return }
        let toStore = batch
        var attempt = 0
        while true {
            do {
                try await storage.store(toStore)
                batch.removeAll(keepingCapacity: true)
                // Entries encrypted before the key became unreadable are written while later ones still wait.
                if isWriting {
                    setStatus(.active)
                }
                return
            } catch {
                attempt += 1
                if attempt >= maxRetries {
                    logger.error("""
                    Dropping \(toStore.count) log entries after \(attempt) failed store \
                    attempts: \(error.localizedDescription)
                    """)
                    setStatus(.failed(String(describing: error)))
                    reportDrops(toStore.count)
                    batch.removeAll(keepingCapacity: true)
                    return
                }
                try? await Task.sleep(for: .milliseconds(50 * attempt))
            }
        }
    }
}
