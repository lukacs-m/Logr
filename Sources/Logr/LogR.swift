import Combine
import Foundation
import Observation
import OSLog

@MainActor
public protocol LogRService: Observable {
    var recentLogs: [LogEntry] { get }

    // Core logging methods
    func log(level: LogLevel,
             message: String,
             category: LogCategory,
             file: String,
             function: String,
             line: Int)

    func exportLogs(format: ExportFormat) async throws -> Data
    func clearLogs() async throws
}

// MARK: - Helper functions

public extension LogRService {
    func debug(_ message: String,
               category: LogCategory = .debug,
               file: String = #file,
               function: String = #function,
               line: Int = #line) {
        log(level: .debug, message: message, category: category, file: file, function: function, line: line)
    }

    func info(_ message: String,
              category: LogCategory = .system,
              file: String = #file,
              function: String = #function,
              line: Int = #line) {
        log(level: .info, message: message, category: category, file: file, function: function, line: line)
    }

    func notice(_ message: String,
                category: LogCategory = .system,
                file: String = #file,
                function: String = #function,
                line: Int = #line) {
        log(level: .notice, message: message, category: category, file: file, function: function, line: line)
    }

    func error(_ message: String,
               category: LogCategory = .system,
               file: String = #file,
               function: String = #function,
               line: Int = #line) {
        log(level: .error, message: message, category: category, file: file, function: function, line: line)
    }

    func fault(_ message: String,
               category: LogCategory = .system,
               file: String = #file,
               function: String = #function,
               line: Int = #line) {
        log(level: .fault, message: message, category: category, file: file, function: function, line: line)
    }
}

@Observable
@MainActor
public final class LogR: LogRService, Sendable {
    public private(set) var recentLogs: [LogEntry] = []

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
                let encryptedLogEntry = EncryptedLogEntry(id: entry.id, timestamp: entry.timestamp,
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
//        return try await storage?.retrieve(
//            levels: levels,
//            categories: categories,
//            subsystems: subsystems,
//            from: startDate,
//            to: endDate,
//            limit: limit
//        ) ?? []
    }

//
//    //TODO: put this logic in array extension
//    public func retrieve(levels: Set<LogLevel>? = nil,
//        categories: Set<LogCategory>? = nil,
//        subsystems: Set<String>? = nil,
//        from startDate: Date? = nil,
//        to endDate: Date? = nil,
//        limit: Int? = nil) async throws -> [LogEntry] {
//        let entries = try await loadEntries()
//
//        var filteredEntries = entries
//
//        if let levels = levels {
//            filteredEntries = filteredEntries.filter { levels.contains($0.level) }
//        }
//
//        if let categories = categories {
//            filteredEntries = filteredEntries.filter { categories.contains($0.category) }
//        }
//
//        if let subsystems = subsystems {
//            filteredEntries = filteredEntries.filter { subsystems.contains($0.subsystem) }
//        }
//
//        if let startDate = startDate {
//            filteredEntries = filteredEntries.filter { $0.timestamp >= startDate }
//        }
//
//        if let endDate = endDate {
//            filteredEntries = filteredEntries.filter { $0.timestamp <= endDate }
//        }
//
//        filteredEntries.sort { $0.timestamp > $1.timestamp }
//
//        if let limit = limit {
//            filteredEntries = Array(filteredEntries.prefix(limit))
//        }
//
//        return filteredEntries
//    }
//

    func clearLogs() async throws {
        try await storage?.clear()
        recentLogs.removeAll()
    }

    func exportLogs(format: ExportFormat = .json) async throws -> Data {
//        let logs = try await storage?.retrieve(
//            levels: nil,
//            categories: nil,
//            subsystems: nil,
//            from: nil,
//            to: nil,
//            limit: nil
//        ) ?? []
        try format.encode(recentLogs)
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
        guard cleanupTask == nil else { return }
        cleanupTask = Task {
            defer { cleanupTask = nil }

            do {
                let cutoffDate = Date().addingTimeInterval(-configuration.maxLogAge)
                try await storage?.deleteEntries(olderThan: cutoffDate)

                let currentCount = try await storage?.count() ?? 0
                if currentCount > configuration.maxLogEntries {
                    try await storage?.deleteEntries(keepingLatest: configuration.maxLogEntries)
                }

                await loadRecentLogs()
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
//            let logs = try await storage?.retrieve(
//                levels: nil,
//                categories: nil,
//                subsystems: nil,
//                from: nil,
//                to: nil,
//                limit: configuration.maxLogEntries
//            ) ?? []
            recentLogs = logs
        } catch {
            getLogger(for: .system).error("Failed to load recent logs: \(error.localizedDescription)")
        }
    }
}

public enum ExportFormat {
    case json
    case csv
    case txt

    public var fileExtension: String {
        switch self {
        case .json: "json"
        case .csv: "csv"
        case .txt: "txt"
        }
    }

    public func encode(_ logs: [LogEntry]) throws -> Data {
        switch self {
        case .json:
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(logs)

        case .csv:
            var csv = "Timestamp,Level,Category,Subsystem,Message,File,Function,Line\n"
            let formatter = ISO8601DateFormatter()

            for log in logs {
                let timestamp = formatter.string(from: log.timestamp)
                let escapedMessage = log.message.replacingOccurrences(of: "\"", with: "\"\"")
                csv += "\"\(timestamp)\",\"\(log.level.rawValue)\",\"\(log.category)\",\"\(log.subsystem)\",\"\(escapedMessage)\",\"\(log.file)\",\"\(log.function)\",\(log.line)\n"
            }

            return csv.data(using: .utf8) ?? Data()

        case .txt:
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .long

            var text = ""
            for log in logs {
                text += "[\(formatter.string(from: log.timestamp))] [\(log.level.displayName.uppercased())] [\(log.category)] \(log.message)\n"
            }

            return text.data(using: .utf8) ?? Data()
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

    private func flush() async {
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
