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
    private var encryptionTasks: [Task<Void, Never>] = []

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
            LogWriterActor(storage: storage, configuration: configuration)
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
        let pendingTasks = encryptionTasks
        let writer = self.writer
        stopTimer()
        if !pendingTasks.isEmpty || writer != nil {
            Task {
                for task in pendingTasks {
                    await task.value
                }
                await writer?.flush()
            }
        }
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

        let task = Task { [weak self, weak writer, cryptoService] in
            do {
                let encryptedLogData = try cryptoService.symmetricEncrypt(object: entry)
                let encryptedLogEntry = EncryptedLogEntry(id: entry.id,
                                                          timestamp: entry.timestamp,
                                                          data: encryptedLogData)
                await writer?.enqueue(encryptedLogEntry)
            } catch {
                self?.droppedLogCount += 1
                self?.getLogger(for: .encryption).log(level: .error, "Failed to encrypt log entry: \(error)")
            }
        }
        encryptionTasks.append(task)
    }
}

// MARK: - Other util functions

public extension LogR {
    func clearLogs() async throws {
        try await storage?.clear()
        recentLogs.removeAll()
    }

    func flush() async {
        let tasks = encryptionTasks
        encryptionTasks.removeAll()
        for task in tasks {
            await task.value
        }

        guard let writer else {
            return
        }

        await writer.flush()
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

// MARK: - Setup & utils

private extension LogR {
    func setup() {
        recentLogs.reserveCapacity(configuration.maxLogEntries)

        setupCategoryLoggers()
        startCleanupTimer()
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
            .publish(every: 1.0, on: .main, in: .common)
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
        recentLogs = recentLogs.filter { $0.timestamp > cutoffDate }
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
            guard let encryptedLogs = try await storage?.fetchEntries() else { return }
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
            recentLogs.append(contentsOf: logs)
        } catch {
            getLogger(for: .system).error("Failed to load recent logs: \(error.localizedDescription)")
        }
    }
}

// MARK: - Background Writer Actor

actor LogWriterActor {
    private let storage: LogRPersistence
    private let logger: Logger
    private var pending: [EncryptedLogEntry] = []
    private var writingTask: Task<Void, Never>?
    private let batchSize: Int

    init(storage: LogRPersistence, configuration: LogrConfiguration, batchSize: Int = 50) {
        self.storage = storage
        self.batchSize = batchSize
        logger = Logger(subsystem: configuration.subsystem, category: LogCategory.persistence.rawValue)
    }

    func enqueue(_ entry: EncryptedLogEntry) {
        pending.append(entry)
        guard writingTask == nil else { return }
        writingTask = Task {
            defer { writingTask = nil }
            await drainPending()
        }
    }

    func flush() async {
        if let writingTask {
            await writingTask.value
        }
        await drainPending()
    }

    private func drainPending() async {
        while !pending.isEmpty {
            let batch = Array(pending.prefix(batchSize))
            pending.removeFirst(batch.count)
            do {
                try await storage.store(batch)
            } catch {
                logger.error("Failed to store log entry: \(error.localizedDescription)")
                break
            }
        }
    }
}

private extension Collections.Deque {
    var toArray: [Element] {
        Array(self)
    }
}
