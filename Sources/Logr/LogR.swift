import Collections
import DequeModule
import Combine
import Foundation
import Observation
import OSLog

@Observable
public final class LogR: LogRService {
    /// Thread-safe backing store for ``recentLogs``, plus the coalescing guard.
    ///
    /// Mutated synchronously *under a lock* on every `log()` — from any isolation domain — so
    /// reads are always current, while the observation notification is dispatched to the main
    /// actor and coalesced (see ``scheduleObservation()``). A burst of logs therefore triggers at
    /// most one SwiftUI invalidation per `coalesceWindowMillis` window, without ever hiding a
    /// logged entry from a reader — including reads made through the `any LogRService` existential.
    private struct CacheState: Sendable {
        var entries = Deque<LogEntry>()
        /// True while a coalescing window is open; guards against scheduling more than one
        /// notification task per window. Flipped under the same lock as `entries`.
        var notificationScheduled = false
        /// Bumped by ``clearLogs()``. A startup ``loadRecentLogs()`` that began before a clear must
        /// not merge its now-wiped historical entries back in (which would resurrect cleared data),
        /// so it checks this value didn't change while it was fetching. Replaces the implicit
        /// main-actor ordering the previously `@MainActor`-isolated load relied on.
        var generation = 0
    }

    @ObservationIgnored
    private let cache: any MutexProtected<CacheState> = SafeMutex.create(CacheState())

    /// Thread-safe and `nonisolated`: callable from any domain. The getter records the observation
    /// dependency (`access`) and returns an O(1) copy-on-write snapshot taken under the lock.
    public nonisolated var recentLogs: Deque<LogEntry> {
        access(keyPath: \.recentLogs)
        return cache.withLock { $0.entries }
    }

    public let configuration: LogrConfiguration

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    @MainActor public var privacyAnalysisResult: PrivacyAnalysisResult? {
        _privacyAnalysisResult as? PrivacyAnalysisResult
    }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    @MainActor public var logIssueSummary: LogIssueSummary? {
        _logIssueSummary as? LogIssueSummary
    }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    @MainActor public var analysisProgress: AnalysisProgress? {
        _analysisProgress as? AnalysisProgress
    }

    @MainActor public var canAnalyseLogs: Bool {
        guard #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *), let analyser else {
            return false
        }
        return analyser.isAvailable
    }

    @MainActor public private(set) var droppedLogCount: Int = 0

    private let storage: LogRPersistence?
    private let cryptoService: any LoggerCryptoServicing

    /// Loggers for the common categories, precomputed once at init. Immutable, so the nonisolated
    /// logging hot path can read it without a lock; uncommon/custom categories fall back to
    /// on-demand `Logger` creation (cheap — a thin handle over `os_log_t`).
    @ObservationIgnored
    private let commonLoggers: [LogCategory: Logger]
    @ObservationIgnored
    private nonisolated(unsafe) var cleanupTimer: AnyCancellable?
    @ObservationIgnored
    @MainActor private var cleanupTask: Task<Void, Never>?

    @ObservationIgnored
    private let writer: LogWriterActor?

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
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    private var analyser: LogAIAnalyzer? {
        _analyser as? LogAIAnalyzer
    }

    /// Designated initializer. `nonisolated`, so a `LogR` can be created from any isolation
    /// domain. `analyser` is type-erased to `any Sendable` because the concrete `LogAIAnalyzer`
    /// types are iOS 26+ and a stored property cannot be `@available`-gated.
    private init(storage: LogRPersistence?,
                 cryptoService: any LoggerCryptoServicing,
                 configuration: LogrConfiguration,
                 analyser: (any Sendable)?) {
        self.storage = storage
        self.configuration = configuration
        self.cryptoService = cryptoService
        _analyser = analyser
        commonLoggers = Self.makeCommonLoggers(subsystem: configuration.subsystem)
        writer = if let storage {
            LogWriterActor(storage: storage, cryptoService: cryptoService, configuration: configuration)
        } else {
            nil
        }
        setup()
    }

    public convenience init(storage: LogRPersistence? = nil,
                            cryptoService: LoggerCryptoServicing,
                            configuration: LogrConfiguration = .default) {
        self.init(storage: storage, cryptoService: cryptoService, configuration: configuration, analyser: nil)
    }

    public convenience init(storage: LogRPersistence? = nil,
                            configuration: LogrConfiguration = .default) throws {
        let crypto = try LoggerCryptoService()
        self.init(storage: storage, cryptoService: crypto, configuration: configuration, analyser: nil)
    }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    public convenience init(storage: LogRPersistence? = nil,
                            logAnalyser: any LogAIAnalyzer = AIAnalyzer(),
                            cryptoService: LoggerCryptoServicing,
                            configuration: LogrConfiguration = .default) {
        self.init(storage: storage, cryptoService: cryptoService, configuration: configuration, analyser: logAnalyser)
    }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    public convenience init(storage: LogRPersistence? = nil,
                            logAnalyser: any LogAIAnalyzer = AIAnalyzer(),
                            configuration: LogrConfiguration = .default) throws {
        let crypto = try LoggerCryptoService()
        self.init(storage: storage, cryptoService: crypto, configuration: configuration, analyser: logAnalyser)
    }

    deinit {
        stopTimer()
        // Finishing the writer's stream lets its consumer drain and persist any buffered
        // entries, then releases it. This is best-effort; call `flush()` when you need a
        // guarantee that pending entries are persisted before termination. Any open
        // coalescing-notification task captures `self` weakly and self-cancels on dealloc.
        writer?.shutdown()
    }

    public nonisolated func log(level: LogLevel,
                                message: @autoclosure () -> String,
                                category: LogCategory,
                                file: String = #file,
                                function: String = #function,
                                line: Int = #line,
                                metadata: [String: LogMetadataValue]? = nil) {
        guard shouldLog(level: level, category: category) else { return }

        let message = message()

        let entry = LogEntry(level: level,
                             category: category,
                             subsystem: configuration.subsystem,
                             message: message,
                             file: file,
                             function: function,
                             line: line,
                             metadata: metadata)

        if configuration.mirrorToOSLog {
            let categoryLogger = logger(for: category)
            if configuration.logVerbosity == .verbose {
                categoryLogger.log(level: level.osLogType,
                                   "[\(category.rawValue)][\(level.rawValue)] \(message) (\(file):\(function):\(line)")
            } else {
                categoryLogger.log(level: level.osLogType, "\(message)")
            }
        }

        // Append synchronously under the lock so every reader — including reads made through the
        // `any LogRService` existential, from any isolation domain — sees the entry at once. The
        // observation *notification* is dispatched to the main actor on a coalesced schedule, so a
        // burst produces a handful of SwiftUI invalidations instead of one per entry, without ever
        // hiding an entry from a reader. The `modify` returns whether this call opened the window.
        let shouldSchedule = cache.modify { state -> Bool in
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
            cache.modify { $0.notificationScheduled = false }
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
        cache.modify { state in
            state.entries.removeAll()
            state.notificationScheduled = false
            // Supersede any in-flight startup load so it can't merge cleared entries back in.
            state.generation &+= 1
        }
        await MainActor.run { notifyObservers() }
        // Clear persisted storage *through the writer* so the clear is ordered against in-flight
        // writes: every entry ingested before this call (including any still buffered in the writer)
        // is discarded, while an entry from a `log()` that races this `await` is ingested *after* the
        // clear marker and therefore survives in both storage and `recentLogs` — they stay
        // consistent. The writer exists exactly when storage does, so this fully covers wiping
        // persisted entries. (If `storage.clear()` fails the error propagates; the in-memory cache is
        // already cleared and storage reloads on next launch.)
        try await writer?.clearPending()
    }

    func flush() async {
        await writer?.flush()
    }
}

// MARK: - Logs analyzer

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
public extension LogR {
    @MainActor
    func scanForPrivacyIssues() async throws -> PrivacyAnalysisResult {
        guard let analyser else {
            throw AIAnalyzerError.missingAnalyzer
        }

        // Reset progress at start
        _analysisProgress = AnalysisProgress.starting(totalLogs: recentLogs.count)

        let result: PrivacyAnalysisResult = if recentLogs.isEmpty {
            PrivacyAnalysisResult.empty
        } else {
            try await analyser.scanForPrivacyIssues(logs: recentLogs.toArray) { progress in
                Task { @MainActor [weak self] in self?._analysisProgress = progress }
            }
        }

        // Clear progress when complete
        _analysisProgress = nil
        _privacyAnalysisResult = result
        return result
    }

    @MainActor
    func summarizeIssues() async throws -> LogIssueSummary {
        guard let analyser else {
            throw AIAnalyzerError.missingAnalyzer
        }

        // Reset progress at start
        _analysisProgress = AnalysisProgress.starting(totalLogs: recentLogs.count)

        let result: LogIssueSummary = if recentLogs.isEmpty {
            LogIssueSummary.empty
        } else {
            try await analyser.summarizeIssues(logs: recentLogs.toArray) { progress in
                Task { @MainActor [weak self] in self?._analysisProgress = progress }
            }
        }

        // Clear progress when complete
        _analysisProgress = nil
        _logIssueSummary = result
        return result
    }
}

// MARK: - Cleanup helpers

extension LogR {
    /// Removes entries older than `cutoff` from a newest-first deque.
    ///
    /// The cache is maintained newest-first, so expired entries always form a
    /// contiguous tail. Trimming from the back is O(number-expired) and allocates
    /// nothing when nothing has expired — unlike a full `filter`, which reallocated the
    /// entire deque on every cleanup tick. Pure (no instance state) so it is `static` and
    /// directly unit-testable.
    static func trimExpiredEntries(_ entries: inout Deque<LogEntry>, olderThan cutoff: Date) {
        while let oldest = entries.last, oldest.timestamp <= cutoff {
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
        current.append(contentsOf: historical.reversed())
        while current.count > cap {
            current.removeLast()
        }
    }
}

// MARK: - Setup & utils

private extension LogR {
    func setup() {
        cache.modify { $0.entries.reserveCapacity(configuration.maxLogEntries) }

        startCleanupTimer()
        if let writer {
            Task {
                await writer.setOnDrop { [weak self] count in
                    Task { @MainActor in self?.droppedLogCount += count }
                }
            }
        }
        Task {
            await loadRecentLogs()
        }
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

    /// Returns the cached logger for a common category, or creates one on demand for uncommon /
    /// custom categories. `nonisolated` and lock-free: `commonLoggers` is immutable and `Logger`
    /// is a cheap, `Sendable` handle.
    nonisolated func logger(for category: LogCategory) -> Logger {
        commonLoggers[category] ?? Logger(subsystem: configuration.subsystem, category: category.rawValue)
    }

    @MainActor
    func performCleanup() {
        let cutoffDate = Date().addingTimeInterval(-configuration.maxLogAge)
        cache.modify { Self.trimExpiredEntries(&$0.entries, olderThan: cutoffDate) }
        notifyObservers()
        guard cleanupTask == nil else { return }
        cleanupTask = Task {
            defer { cleanupTask = nil }
            do {
                try await storage?.deleteEntries(olderThan: cutoffDate)

                let currentCount = try await storage?.count() ?? 0
                if currentCount > configuration.maxLogEntries {
                    try await storage?.deleteEntries(keepingLatest: configuration.maxLogEntries)
                }
            } catch {
                logger(for: .system).error("Cleanup failed: \(error.localizedDescription)")
            }
        }
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
    private func loadRecentLogs() async {
        do {
            // Snapshot the cache generation before fetching. If a `clearLogs()` bumps it while we
            // load, the merge below is skipped — the loaded history was cleared from storage too,
            // so resurrecting it in memory would be a bug (see ``CacheState/generation``).
            let generationAtStart = cache.withLock { $0.generation }
            // Load at most as many entries as the in-memory cache holds, rather than the
            // entire persisted history.
            guard let encryptedLogs = try await storage?.fetchEntries(limit: configuration.maxLogEntries)
            else { return }
            var logs: [LogEntry] = []
            var decryptionFailures = 0
            for encrypted in encryptedLogs {
                do {
                    let entry: LogEntry = try cryptoService.symmetricDecrypt(encryptedData: encrypted.data)
                    logs.append(entry)
                } catch {
                    decryptionFailures += 1
                }
            }
            if decryptionFailures > 0 {
                logger(for: .encryption)
                    .warning("Failed to decrypt \(decryptionFailures) of \(encryptedLogs.count) log entries")
            }
            let loaded = logs
            let didMerge = cache.modify { state -> Bool in
                guard state.generation == generationAtStart else { return false }
                Self.mergeLoaded(loaded, into: &state.entries, cap: configuration.maxLogEntries)
                return true
            }
            if didMerge {
                await MainActor.run { notifyObservers() }
            }
        } catch {
            logger(for: .system).error("Failed to load recent logs: \(error.localizedDescription)")
        }
    }
}

// MARK: - Background Writer Actor

/// Background actor that encrypts and persists log entries.
///
/// Plaintext entries are handed in synchronously via ``ingest(_:)`` and delivered to a
/// single consumer over an `AsyncStream`. The consumer encrypts each entry off the main
/// actor, accumulates a batch, and writes it to storage with retry-on-failure. Using one
/// ordered consumer means the caller never spawns a per-log task, nothing accumulates on
/// the main actor, and entries are persisted in the order they were logged.
///
/// ## Backpressure
///
/// The number of entries buffered between ``ingest(_:)`` and the consumer is capped at
/// `maxPendingWrites`. If storage falls behind under a sustained burst, the *newest* entries
/// are shed (the oldest — likely the cause being diagnosed — are kept) and counted, rather
/// than letting the buffer grow without bound. Shed counts are reported through the same
/// `onDrop` callback as encryption/retry failures. The cap is applied only to entries:
/// `flush`/`shutdown` control signals are never dropped, so `flush()` can never hang.
actor LogWriterActor {
    /// Events delivered to the single consumer.
    private enum Event {
        case entry(LogEntry)
        case flush(CheckedContinuation<Void, Never>)
        /// Discards any not-yet-persisted entries buffered ahead of this signal and clears storage.
        /// Routed through the same stream as `entry`, so it is ordered *after* every entry ingested
        /// before the `clear()` call (those are dropped) and *before* any ingested after it.
        case clear(CheckedContinuation<Void, Error>)
    }

    /// Mutex-guarded backpressure state, shared between the nonisolated `ingest` producer and the
    /// actor-isolated consumer. `inFlight` counts entries yielded but not yet consumed; `pendingDrops`
    /// accumulates shed entries until the consumer can report them via `onDrop`.
    private struct Backlog: Sendable {
        var inFlight = 0
        var pendingDrops = 0
    }

    private let storage: LogRPersistence
    private let cryptoService: any LoggerCryptoServicing
    private let logger: Logger
    private let batchSize: Int
    private let maxRetries: Int
    private let maxPendingWrites: Int
    private let continuation: AsyncStream<Event>.Continuation
    /// `let` of a `Sendable` type, so the nonisolated producer can touch it without hopping actors.
    private let backlog: any MutexProtected<Backlog> = SafeMutex.create(Backlog())
    private var onDrop: (@Sendable (Int) -> Void)?

    init(storage: LogRPersistence,
         cryptoService: any LoggerCryptoServicing,
         configuration: LogrConfiguration,
         batchSize: Int = 50,
         maxRetries: Int = 3,
         maxPendingWrites: Int = 100_000) {
        self.storage = storage
        self.cryptoService = cryptoService
        self.batchSize = batchSize
        self.maxRetries = maxRetries
        self.maxPendingWrites = max(1, maxPendingWrites)
        logger = Logger(subsystem: configuration.subsystem, category: LogCategory.persistence.rawValue)
        let (stream, continuation) = AsyncStream<Event>.makeStream()
        self.continuation = continuation
        Task { await self.consume(stream) }
    }

    /// Registers a callback invoked with the number of entries dropped (encryption failures, a
    /// batch abandoned after exhausting retries, or entries shed under backpressure).
    func setOnDrop(_ handler: @escaping @Sendable (Int) -> Void) {
        onDrop = handler
    }

    /// Hands a plaintext entry to the writer. Synchronous and non-isolated so the main
    /// actor's logging hot path neither awaits nor spawns a task. Sheds the entry (and counts
    /// it) when the pending buffer is already at `maxPendingWrites`, so memory stays bounded.
    nonisolated func ingest(_ entry: LogEntry) {
        let cap = maxPendingWrites
        let accepted = backlog.modify { state -> Bool in
            guard state.inFlight < cap else {
                state.pendingDrops += 1
                return false
            }
            state.inFlight += 1
            return true
        }
        guard accepted else { return }
        continuation.yield(.entry(entry))
    }

    /// Suspends until every entry enqueued before this call has been persisted.
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
    /// consumer's in-flight writes. Throws if the underlying `storage.clear()` fails.
    nonisolated func clearPending() async throws {
        try await withCheckedThrowingContinuation { (awaiter: CheckedContinuation<Void, Error>) in
            // Stream already finished (post-`shutdown()`): nothing left to persist or clear.
            if case .terminated = continuation.yield(.clear(awaiter)) {
                awaiter.resume()
            }
        }
    }

    /// Ends the stream so the consumer drains its buffer and exits. Best-effort.
    nonisolated func shutdown() {
        continuation.finish()
    }
}

private extension LogWriterActor {
    private func consume(_ stream: AsyncStream<Event>) async {
        var batch: [EncryptedLogEntry] = []
        batch.reserveCapacity(batchSize)
        for await event in stream {
            switch event {
            case let .entry(entry):
                reportBackpressureDrops(consumedInFlight: 1)
                if let encrypted = encrypt(entry) {
                    batch.append(encrypted)
                    if batch.count >= batchSize {
                        await store(&batch)
                    }
                }
            case let .flush(awaiter):
                reportBackpressureDrops(consumedInFlight: 0)
                await store(&batch)
                awaiter.resume()
            case let .clear(awaiter):
                reportBackpressureDrops(consumedInFlight: 0)
                // Drop entries logged before the clear that haven't been persisted yet, then wipe
                // storage. Entries delivered *after* this event survive (they were ingested after
                // the caller asked to clear).
                batch.removeAll(keepingCapacity: true)
                do {
                    try await storage.clear()
                    awaiter.resume()
                } catch {
                    awaiter.resume(throwing: error)
                }
            }
        }
        // Stream finished (shutdown): persist whatever is still buffered.
        await store(&batch)
    }

    /// Decrements the in-flight count for the entry just consumed and forwards any entries shed
    /// under backpressure since the last report to `onDrop`, so callers can surface the loss.
    func reportBackpressureDrops(consumedInFlight: Int) {
        let dropped = backlog.modify { state -> Int in
            state.inFlight -= consumedInFlight
            let pending = state.pendingDrops
            state.pendingDrops = 0
            return pending
        }
        if dropped > 0 {
            logger.error("Shed \(dropped) log entries under backpressure (storage fell behind)")
            onDrop?(dropped)
        }
    }

    func encrypt(_ entry: LogEntry) -> EncryptedLogEntry? {
        do {
            let data = try cryptoService.symmetricEncrypt(object: entry)
            return EncryptedLogEntry(id: entry.id, timestamp: entry.timestamp, data: data)
        } catch {
            logger.error("Failed to encrypt log entry: \(error.localizedDescription)")
            onDrop?(1)
            return nil
        }
    }

    /// Stores `batch`, retrying with linear backoff. Entries are cleared only after a
    /// successful write, so a transient failure never loses data. After `maxRetries`
    /// failures the batch is dropped (and reported via `onDrop`) so the loop can't stall.
    func store(_ batch: inout [EncryptedLogEntry]) async {
        guard !batch.isEmpty else { return }
        let toStore = batch
        var attempt = 0
        while true {
            do {
                try await storage.store(toStore)
                batch.removeAll(keepingCapacity: true)
                return
            } catch {
                attempt += 1
                if attempt >= maxRetries {
                    logger.error("""
                    Dropping \(toStore.count) log entries after \(attempt) failed store \
                    attempts: \(error.localizedDescription)
                    """)
                    onDrop?(toStore.count)
                    batch.removeAll(keepingCapacity: true)
                    return
                }
                try? await Task.sleep(for: .milliseconds(50 * attempt))
            }
        }
    }
}

private extension Collections.Deque {
    var toArray: [Element] {
        Array(self)
    }
}
