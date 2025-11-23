import Combine
import Foundation
import Observation
import OSLog

@Observable
@MainActor
public final class LogR: LogRService, Sendable {
    public private(set) var recentLogs: [LogEntry] = []

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    public var privacyAnalysisResult: PrivacyAnalysisResult? {
        _privacyAnalysisResult as? PrivacyAnalysisResult
    }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    public var logIssueSummary: LogIssueSummary? {
        _logIssueSummary as? LogIssueSummary
    }

    private let storage: LogRPersistence?
    private let configuration: LogrConfiguration
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
    private var _analyser: (any SendableMetatype)?
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    private var analyser: LogAIAnalyzer? {
        _analyser as? LogAIAnalyzer
    }

    public var canAnalyseLogs: Bool {
        guard #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *), let analyser else {
            return false
        }
        return analyser.isAvailable
    }

    public init(storage: LogRPersistence? = nil,
                cryptoService: LoggerCryptoServicing = LoggerCryptoService(),
                configuration: LogrConfiguration = .default) {
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

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    public convenience init(storage: LogRPersistence? = nil,
                            logAnalyser: any LogAIAnalyzer = AIAnalyzer(),
                            cryptoService: LoggerCryptoServicing = LoggerCryptoService(),
                            configuration: LogrConfiguration = .default) {
        self.init(storage: storage, cryptoService: cryptoService, configuration: configuration)
        _analyser = logAnalyser
    }

    deinit {
        stopTimer()
    }

    public func log(level: LogLevel,
                    message: String,
                    category: LogCategory,
                    file: String = #file,
                    function: String = #function,
                    line: Int = #line) {
        guard shouldLog(level: level) else { return }

        let entry = LogEntry(level: level,
                             category: category,
                             subsystem: configuration.subsystem,
                             message: message,
                             file: file,
                             function: function,
                             line: line)

        let categoryLogger = getLogger(for: category)

        if configuration.logVerbosity == .verbose {
            categoryLogger.log(level: level.osLogType,
                               "[\(category.rawValue)][\(level.rawValue)] \(message) (\(file):\(function):\(line)")
        } else {
            categoryLogger.log(level: level.osLogType, "\(message)")
        }

        recentLogs.insert(entry, at: 0)
        if recentLogs.count > configuration.maxLogEntries {
            recentLogs.removeLast()
        }

        Task { [weak writer, cryptoService] in
            do {
                let encryptedLogData = try cryptoService.symmetricEncrypt(object: entry)
                let encryptedLogEntry = EncryptedLogEntry(id: entry.id,
                                                          timestamp: entry.timestamp,
                                                          data: encryptedLogData)
                await writer?.enqueue(encryptedLogEntry)
            } catch {
                getLogger(for: .encryption).log(level: .error, "Failed to encrypt log entry: \(error)")
            }
        }
    }
}

// MARK: - Other util functions

public extension LogR {
    func getLogs(levels: Set<LogLevel>? = nil,
                 categories: Set<LogCategory>? = nil,
                 subsystems: Set<String>? = nil,
                 from startDate: Date? = nil,
                 to endDate: Date? = nil,
                 limit: Int? = nil) throws -> [LogEntry] {
        guard !recentLogs.isEmpty else {
            return []
        }
        var filteredEntries = recentLogs

        if let levels {
            filteredEntries = filteredEntries.filter { levels.contains($0.level) }
        }

        if let categories {
            filteredEntries = filteredEntries.filter { categories.contains($0.category) }
        }

        if let subsystems {
            filteredEntries = filteredEntries.filter { subsystems.contains($0.subsystem) }
        }

        if let startDate {
            filteredEntries = filteredEntries.filter { $0.timestamp >= startDate }
        }

        if let endDate {
            filteredEntries = filteredEntries.filter { $0.timestamp <= endDate }
        }

        filteredEntries.sort { $0.timestamp > $1.timestamp }

        if let limit {
            filteredEntries = Array(filteredEntries.prefix(limit))
        }

        return filteredEntries
    }

    func clearLogs() async throws {
        try await storage?.clear()
        recentLogs.removeAll()
    }

    func exportLogs(format: ExportFormat = .json) -> Data? {
        encode(for: format)
    }
    
    func flush() async {
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
        let result = if recentLogs.isEmpty {
            PrivacyAnalysisResult.empty
        } else {
            try await analyser.scanForPrivacyIssues(logs: recentLogs)
        }

        _privacyAnalysisResult = result
        return result
    }

    func summarizeIssues() async throws -> LogIssueSummary {
        guard let analyser else {
            throw AIAnalyzerError.missingAnalyzer
        }
        let result = if recentLogs.isEmpty {
            LogIssueSummary.empty
        } else {
            try await analyser.summarizeIssues(logs: recentLogs)
        }

        _logIssueSummary = result
        return result
    }
}

// MARK: - Setup & utils

private extension LogR {
    func setup() {
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

    func shouldLog(level: LogLevel) -> Bool {
        configuration.enabledLevels.contains(level)
    }
}

// MARK: - Local storage

private extension LogR {
    private func loadRecentLogs() async {
        do {
            let encryptedLogs = try await storage?.fetchEntries()
            let logs: [LogEntry] = encryptedLogs?
                .compactMap { try? cryptoService.symmetricDecrypt(encryptedData: $0.data) } ?? []
            recentLogs.append(contentsOf: logs)
        } catch {
            getLogger(for: .system).error("Failed to load recent logs: \(error.localizedDescription)")
        }
    }
}

// MARK: - Export

private extension LogR {
    // TODO: check other for export formatting
    func encode(for exportFormat: ExportFormat) -> Data? {
        guard !recentLogs.isEmpty else { return nil }
        switch exportFormat {
        case .json:
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try? encoder.encode(recentLogs)

        case .csv:
            var csv = "Timestamp,Level,Category,Subsystem,Message,File,Function,Line\n"
            let formatter = ISO8601DateFormatter()

            for log in recentLogs {
                let timestamp = formatter.string(from: log.timestamp)
                let escapedMessage = log.message.replacingOccurrences(of: "\"", with: "\"\"")
                csv += "\"\(timestamp)\",\"\(log.level.rawValue)\",\"\(log.category)\",\"\(log.subsystem)\",\"\(escapedMessage)\",\"\(log.file)\",\"\(log.function)\",\(log.line)\n"
            }

            return csv.data(using: .utf8)

        case .txt:
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .long

            var text = ""
            for log in recentLogs {
                text += "[\(formatter.string(from: log.timestamp))] [\(log.level.displayName.uppercased())] [\(log.category)] \(log.message)\n"
            }

            return text.data(using: .utf8)
        }
    }
}

// MARK: - Background Writer Actor

actor LogWriterActor {
    private let storage: LogRPersistence
    private let logger: Logger
    private var pending: [EncryptedLogEntry] = []
    private var isWritingTask: Task<Void, Never>?

    init(storage: LogRPersistence, configuration: LogrConfiguration) {
        self.storage = storage
        logger = Logger(subsystem: configuration.subsystem, category: LogCategory.persistence.rawValue)
    }

    func enqueue(_ entry: EncryptedLogEntry) {
        pending.append(entry)
        guard isWritingTask == nil else { return }
        isWritingTask = Task {
            defer { isWritingTask = nil }
            await flush()
        }
    }

    func flush() async {
        while !pending.isEmpty {
            let entry = pending.removeFirst()
            do {
                try await storage.store(entry)
            } catch {
                logger.error("Failed to store log entry: \(error.localizedDescription)")
            }
        }
    }
}
