import Collections
import DequeModule
import Combine
import Foundation
import Observation
import OSLog

@Observable
@MainActor
public final class LogR: LogRService {
    /// Backing store for ``recentLogs``. Mutated synchronously on every `log()` so reads are
    /// always current, while the observation notification is fired separately and coalesced
    /// (see ``scheduleObservation()``). A burst of logs therefore triggers at most one SwiftUI
    /// invalidation per `coalesceWindowMillis` window, without ever hiding a logged entry from a
    /// reader — including reads made through the `any LogRService` existential.
    @ObservationIgnored private var _recentLogs: Deque<LogEntry>

    public var recentLogs: Deque<LogEntry> {
        access(keyPath: \.recentLogs)
        return _recentLogs
    }

    public let configuration: LogrConfiguration

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    public var privacyAnalysisResult: PrivacyAnalysisResult? {
        _privacyAnalysisResult as? PrivacyAnalysisResult
    }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    public var logIssueSummary: LogIssueSummary? {
        _logIssueSummary as? LogIssueSummary
    }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    public var analysisProgress: AnalysisProgress? {
        _analysisProgress as? AnalysisProgress
    }

    public var canAnalyseLogs: Bool {
        guard #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *), let analyser else {
            return false
        }
        return analyser.isAvailable
    }

    public private(set) var droppedLogCount: Int = 0

    private let storage: LogRPersistence?
    private let cryptoService: any LoggerCryptoServicing

    @ObservationIgnored
    private var categoryLoggers: [LogCategory: Logger] = [:]
    @ObservationIgnored
    private nonisolated(unsafe) var cleanupTimer: AnyCancellable?
    @ObservationIgnored
    private var cleanupTask: Task<Void, Never>?

    @ObservationIgnored
    private let writer: LogWriterActor?

    /// The open observation-coalescing window, if any. While non-nil, logging keeps mutating
    /// `_recentLogs` (so reads stay current) but defers the observation notification until the
    /// window closes, so a burst produces a single SwiftUI invalidation. Cancelled on
    /// `deinit`/`clearLogs`. `nonisolated(unsafe)` so the nonisolated `deinit` can cancel it; all
    /// live accesses are on the main actor, and `deinit` only runs once no other reference
    /// (including the task) is alive.
    @ObservationIgnored
    private nonisolated(unsafe) var observationWindow: Task<Void, Never>?

    // Type-erased to `Any?` so these stored properties carry no `@available` requirement (a stored
    // property cannot be annotated `@available`, and the analyzer types are iOS 26+). All access is
    // through the main-actor-isolated, availability-gated computed properties below, which downcast
    // back to the concrete type — so the erasure is safe and the metatype-only `SendableMetatype`
    // (which every type trivially satisfies) bought nothing.
    private var _logIssueSummary: Any?
    private var _privacyAnalysisResult: Any?
    private var _analysisProgress: Any?
    private var _analyser: Any?
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    private var analyser: LogAIAnalyzer? {
        _analyser as? LogAIAnalyzer
    }

    public init(storage: LogRPersistence? = nil,
                cryptoService: LoggerCryptoServicing,
                configuration: LogrConfiguration = .default) {
        _recentLogs = Deque()
        self.storage = storage
        self.configuration = configuration
        self.cryptoService = cryptoService
        writer = if let storage {
            LogWriterActor(storage: storage, cryptoService: cryptoService, configuration: configuration)
        } else {
            nil
        }
        setup()
    }

    public convenience init(storage: LogRPersistence? = nil,
                            configuration: LogrConfiguration = .default) throws {
        let crypto = try LoggerCryptoService()
        self.init(storage: storage, cryptoService: crypto, configuration: configuration)
    }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    public convenience init(storage: LogRPersistence? = nil,
                            logAnalyser: any LogAIAnalyzer = AIAnalyzer(),
                            cryptoService: LoggerCryptoServicing,
                            configuration: LogrConfiguration = .default) {
        self.init(storage: storage, cryptoService: cryptoService, configuration: configuration)
        _analyser = logAnalyser
    }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    public convenience init(storage: LogRPersistence? = nil,
                            logAnalyser: any LogAIAnalyzer = AIAnalyzer(),
                            configuration: LogrConfiguration = .default) throws {
        let crypto = try LoggerCryptoService()
        self.init(storage: storage, logAnalyser: logAnalyser, cryptoService: crypto, configuration: configuration)
    }

    deinit {
        stopTimer()
        // Cancel any open observation-coalescing window. No data is lost: every entry was already
        // appended to `_recentLogs` synchronously and handed to the writer via `ingest`; only a
        // pending (purely cosmetic) observation notification is dropped.
        observationWindow?.cancel()
        // Finishing the writer's stream lets its consumer drain and persist any buffered
        // entries, then releases it. This is best-effort; call `flush()` when you need a
        // guarantee that pending entries are persisted before termination.
        writer?.shutdown()
    }

    public func log(level: LogLevel,
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
            let categoryLogger = getLogger(for: category)
            if configuration.logVerbosity == .verbose {
                categoryLogger.log(level: level.osLogType,
                                   "[\(category.rawValue)][\(level.rawValue)] \(message) (\(file):\(function):\(line)")
            } else {
                categoryLogger.log(level: level.osLogType, "\(message)")
            }
        }

        // Append synchronously so every reader — including reads made through the
        // `any LogRService` existential — sees the entry at once. The observation *notification*
        // is fired on a coalesced schedule, so a burst of logs produces a handful of SwiftUI
        // invalidations instead of one per entry, without ever hiding an entry from a reader.
        _recentLogs.prepend(entry)
        while _recentLogs.count > configuration.maxLogEntries {
            _recentLogs.removeLast()
        }
        scheduleObservation()

        // Hand the entry to the background writer. Encryption and batched persistence
        // happen inside the actor's single consumer — no per-call Task is spawned and
        // nothing accumulates on the main actor.
        writer?.ingest(entry)
    }
}

// MARK: - Coalesced observation

private extension LogR {
    /// Notifies observers immediately if no window is open (so an isolated log invalidates at
    /// once), then opens a window during which further logs mutate `_recentLogs` silently and a
    /// single notification is fired when it closes. The result: at most one SwiftUI invalidation
    /// per window, no matter how fast logs arrive. The data is never withheld — only the
    /// notification is coalesced.
    func scheduleObservation() {
        guard observationWindow == nil else { return }
        notifyObservers()
        let windowMillis = max(0, configuration.coalesceWindowMillis)
        observationWindow = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(windowMillis))
            guard let self else { return }
            // Close the window before notifying so a log arriving during the notification reopens one.
            observationWindow = nil
            notifyObservers()
        }
    }

    /// Fires the observation for `recentLogs` without mutating it (the data was already updated
    /// synchronously in `log()`), so SwiftUI re-reads the current value.
    func notifyObservers() {
        withMutation(keyPath: \.recentLogs) {}
    }
}

// MARK: - Other util functions

public extension LogR {
    func clearLogs() async throws {
        // Wipe the in-memory cache synchronously, *before* the suspension below — no `log()` can
        // interleave between the cancel and the removeAll. Cancel any open coalescing window first
        // so a pending notification can't fire against the cleared cache.
        observationWindow?.cancel()
        observationWindow = nil
        withMutation(keyPath: \.recentLogs) {
            _recentLogs.removeAll()
        }
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
    /// `_recentLogs` is maintained newest-first, so expired entries always form a
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
    /// oldest). This keeps `_recentLogs` newest-first and never larger than `maxLogEntries`.
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
        _recentLogs.reserveCapacity(configuration.maxLogEntries)

        setupCategoryLoggers()
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

    func setupCategoryLoggers() {
        // Create loggers for common categories
        for category in LogCategory.common {
            categoryLoggers[category] = Logger(subsystem: configuration.subsystem, category: category.rawValue)
        }
    }

    func startCleanupTimer() {
        cleanupTimer = Timer
            .publish(every: configuration.cleanupInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.performCleanup()
            }
    }

    func getLogger(for category: LogCategory) -> Logger {
        if let logger = categoryLoggers[category] {
            return logger
        }

        // Create new logger for this category and cache it
        let logger = Logger(subsystem: configuration.subsystem, category: category.rawValue)
        categoryLoggers[category] = logger
        return logger
    }

    func performCleanup() {
        let cutoffDate = Date().addingTimeInterval(-configuration.maxLogAge)
        withMutation(keyPath: \.recentLogs) {
            Self.trimExpiredEntries(&_recentLogs, olderThan: cutoffDate)
        }
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
                getLogger(for: .system).error("Cleanup failed: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func stopTimer() {
        cleanupTimer?.cancel()
        cleanupTimer = nil
    }

    func shouldLog(level: LogLevel, category: LogCategory) -> Bool {
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
                getLogger(for: .encryption)
                    .warning("Failed to decrypt \(decryptionFailures) of \(encryptedLogs.count) log entries")
            }
            withMutation(keyPath: \.recentLogs) {
                Self.mergeLoaded(logs, into: &_recentLogs, cap: configuration.maxLogEntries)
            }
        } catch {
            getLogger(for: .system).error("Failed to load recent logs: \(error.localizedDescription)")
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
