import Collections
import DequeModule
import Combine
import Foundation
import Observation
import OSLog

@Observable
@MainActor
public final class LogR: LogRService, Sendable {
    public private(set) var recentLogs: Deque<LogEntry>
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

    private var _logIssueSummary: (any SendableMetatype)?
    private var _privacyAnalysisResult: (any SendableMetatype)?
    private var _analysisProgress: (any SendableMetatype)?
    private var _analyser: (any SendableMetatype)?
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    private var analyser: LogAIAnalyzer? {
        _analyser as? LogAIAnalyzer
    }

    @ObservationIgnored
    private nonisolated(unsafe) var progressTask: Task<Void, Never>?

    public init(storage: LogRPersistence? = nil,
                cryptoService: LoggerCryptoServicing,
                configuration: LogrConfiguration = .default) {
        recentLogs = Deque()
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

        let categoryLogger = getLogger(for: category)

        if configuration.logVerbosity == .verbose {
            categoryLogger.log(level: level.osLogType,
                               "[\(category.rawValue)][\(level.rawValue)] \(message) (\(file):\(function):\(line)")
        } else {
            categoryLogger.log(level: level.osLogType, "\(message)")
        }

        if recentLogs.count >= configuration.maxLogEntries {
            _ = recentLogs.popLast()
        }
        recentLogs.prepend(entry)

        // Hand the entry to the background writer. Encryption and batched persistence
        // happen inside the actor's single consumer — no per-call Task is spawned and
        // nothing accumulates on the main actor.
        writer?.ingest(entry)
    }
}

// MARK: - Other util functions

public extension LogR {
    func clearLogs() async throws {
        try await storage?.clear()
        recentLogs.removeAll()
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
            try await analyser.scanForPrivacyIssues(logs: recentLogs.toArray) { [weak self] progress in
                self?.updateProgress(progress: progress)
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
            try await analyser.summarizeIssues(logs: recentLogs.toArray) { [weak self] progress in
                self?.updateProgress(progress: progress)
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
    /// `recentLogs` is maintained newest-first, so expired entries always form a
    /// contiguous tail. Trimming from the back is O(number-expired) and allocates
    /// nothing when nothing has expired — unlike a full `filter`, which reallocated the
    /// entire deque on every cleanup tick.
    func trimExpiredEntries(_ entries: inout Deque<LogEntry>, olderThan cutoff: Date) {
        while let oldest = entries.last, oldest.timestamp <= cutoff {
            entries.removeLast()
        }
    }

    /// Merges history loaded from storage into the in-memory cache.
    ///
    /// `historical` arrives oldest-first (as returned by `fetchEntries(limit:)`), while
    /// `current` holds any logs captured during launch, newest-first. History is appended
    /// newest-first after those live logs, then the cache is trimmed to `cap` (dropping the
    /// oldest). This keeps `recentLogs` newest-first and never larger than `maxLogEntries`.
    func mergeLoaded(_ historical: [LogEntry], into current: inout Deque<LogEntry>, cap: Int) {
        current.append(contentsOf: historical.reversed())
        while current.count > cap {
            current.removeLast()
        }
    }
}

// MARK: - Setup & utils

private extension LogR {
    func setup() {
        recentLogs.reserveCapacity(configuration.maxLogEntries)

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
        trimExpiredEntries(&recentLogs, olderThan: cutoffDate)
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

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    nonisolated func updateProgress(progress: AnalysisProgress) {
        progressTask?.cancel()
        progressTask = Task { @MainActor [weak self] in
            self?._analysisProgress = progress
        }
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
           mergeLoaded(logs, into: &recentLogs, cap: configuration.maxLogEntries)
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
actor LogWriterActor {
    /// Events delivered to the single consumer.
    private enum Event {
        case entry(LogEntry)
        case flush(CheckedContinuation<Void, Never>)
    }

    private let storage: LogRPersistence
    private let cryptoService: any LoggerCryptoServicing
    private let logger: Logger
    private let batchSize: Int
    private let maxRetries: Int
    private let continuation: AsyncStream<Event>.Continuation
    private var onDrop: (@Sendable (Int) -> Void)?

    init(storage: LogRPersistence,
         cryptoService: any LoggerCryptoServicing,
         configuration: LogrConfiguration,
         batchSize: Int = 50,
         maxRetries: Int = 3) {
        self.storage = storage
        self.cryptoService = cryptoService
        self.batchSize = batchSize
        self.maxRetries = maxRetries
        logger = Logger(subsystem: configuration.subsystem, category: LogCategory.persistence.rawValue)
        let (stream, continuation) = AsyncStream<Event>.makeStream()
        self.continuation = continuation
        Task { await self.consume(stream) }
    }

    /// Registers a callback invoked with the number of entries dropped (encryption
    /// failures, or a batch abandoned after exhausting retries).
    func setOnDrop(_ handler: @escaping @Sendable (Int) -> Void) {
        onDrop = handler
    }

    /// Hands a plaintext entry to the writer. Synchronous and non-isolated so the main
    /// actor's logging hot path neither awaits nor spawns a task.
    nonisolated func ingest(_ entry: LogEntry) {
        continuation.yield(.entry(entry))
    }

    /// Suspends until every entry enqueued before this call has been persisted.
    nonisolated func flush() async {
        await withCheckedContinuation { awaiter in
            continuation.yield(.flush(awaiter))
        }
    }

    /// Ends the stream so the consumer drains its buffer and exits. Best-effort.
    nonisolated func shutdown() {
        continuation.finish()
    }

    private func consume(_ stream: AsyncStream<Event>) async {
        var batch: [EncryptedLogEntry] = []
        batch.reserveCapacity(batchSize)
        for await event in stream {
            switch event {
            case let .entry(entry):
                if let encrypted = encrypt(entry) {
                    batch.append(encrypted)
                    if batch.count >= batchSize {
                        await store(&batch)
                    }
                }
            case let .flush(awaiter):
                await store(&batch)
                awaiter.resume()
            }
        }
        // Stream finished (shutdown): persist whatever is still buffered.
        await store(&batch)
    }

    private func encrypt(_ entry: LogEntry) -> EncryptedLogEntry? {
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
    private func store(_ batch: inout [EncryptedLogEntry]) async {
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
