import Foundation
import OSLog
import Observation

@Observable
@MainActor
public final class LogR: Sendable {
    public private(set) var recentLogs: [LogEntry] = []
    public private(set) var isCleanupRunning = false
    
    private let storage: PersistentStorage
    private let configuration: LogrConfiguration
    private let logger: Logger
    private var cleanupTask: Task<Void, Never>?
    
    public static let shared = LogR()
    
    public init(
        storage: PersistentStorage? = nil,
        configuration: LogrConfiguration = .default
    ) {
        self.storage = storage ?? (try! FileSystemStorage())
        self.configuration = configuration
        self.logger = Logger(subsystem: configuration.subsystem, category: "LogR")
        
        startCleanupTimer()
        Task {
            await loadRecentLogs()
        }
    }
    
    deinit {
//        Task { @MainActor in
//            cleanupTask?.cancel()
//        }
    }
    
    private func startCleanupTimer() {
        cleanupTask?.cancel()
        cleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.configuration.cleanupInterval ?? 3600))
                await self?.performCleanup()
            }
        }
    }
    
    private func performCleanup() async {
        isCleanupRunning = true
        defer { isCleanupRunning = false }
        
        do {
            let cutoffDate = Date().addingTimeInterval(-configuration.maxLogAge)
            try await storage.deleteEntries(olderThan: cutoffDate)
            
            let currentCount = try await storage.count()
            if currentCount > configuration.maxLogEntries {
                try await storage.deleteEntries(keepingLatest: configuration.maxLogEntries)
            }
            
            await loadRecentLogs()
        } catch {
            logger.error("Cleanup failed: \(error.localizedDescription)")
        }
    }
    
    private func loadRecentLogs() async {
        do {
            let logs = try await storage.retrieve(
                levels: nil,
                categories: nil,
                subsystems: nil,
                from: nil,
                to: nil,
                limit: configuration.maxLogEntries
            )
            recentLogs = logs
        } catch {
            logger.error("Failed to load recent logs: \(error.localizedDescription)")
        }
    }
    
    public func log(
        level: LogLevel,
        message: String,
        category: String = "default",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) async {
        guard configuration.shouldLog(level: level) else { return }
        
        let entry = LogEntry(
            level: level,
            category: category,
            subsystem: configuration.subsystem,
            message: message,
            file: file,
            function: function,
            line: line
        )
        
        logger.log(level: level.osLogType, "\(message)")
        
        do {
            try await storage.store(entry)
            recentLogs.insert(entry, at: 0)
            if recentLogs.count > configuration.maxLogEntries {
                recentLogs.removeLast()
            }
        } catch {
            logger.error("Failed to store log entry: \(error.localizedDescription)")
        }
    }
    
    public func log(
        level: LogLevel,
        message: String,
        privateData: PrivateString,
        category: String = "default",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) async {
        guard configuration.shouldLog(level: level) else { return }
        
        let fullMessage = "\(message) \(privateData.redacted)"
        let entry = LogEntry(
            level: level,
            category: category,
            subsystem: configuration.subsystem,
            message: fullMessage,
            file: file,
            function: function,
            line: line
        )
        
        switch privateData.privacy {
        case .public:
            logger.log(level: level.osLogType, "\(message, privacy: .public) \(privateData.value, privacy: .public)")
        case .private:
            logger.log(level: level.osLogType, "\(message, privacy: .public) \(privateData.value, privacy: .private)")
        case .sensitive:
            logger.log(level: level.osLogType, "\(message, privacy: .public) \(privateData.value, privacy: .sensitive)")
        }
        
        do {
            try await storage.store(entry)
            recentLogs.insert(entry, at: 0)
            if recentLogs.count > 1000 {
                recentLogs.removeLast()
            }
        } catch {
            logger.error("Failed to store log entry: \(error.localizedDescription)")
        }
    }
    
    public func debug(
        _ message: String,
        category: String = "default",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) async {
        await log(level: .debug, message: message, category: category, file: file, function: function, line: line)
    }
    
    public func info(
        _ message: String,
        category: String = "default",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) async {
        await log(level: .info, message: message, category: category, file: file, function: function, line: line)
    }
    
    public func notice(
        _ message: String,
        category: String = "default",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) async {
        await log(level: .notice, message: message, category: category, file: file, function: function, line: line)
    }
    
    public func error(
        _ message: String,
        category: String = "default",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) async {
        await log(level: .error, message: message, category: category, file: file, function: function, line: line)
    }
    
    public func fault(
        _ message: String,
        category: String = "default",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) async {
        await log(level: .fault, message: message, category: category, file: file, function: function, line: line)
    }
    
    public func debug(
        _ message: String,
        privateData: PrivateString,
        category: String = "default",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) async {
        await log(level: .debug, message: message, privateData: privateData, category: category, file: file, function: function, line: line)
    }
    
    public func info(
        _ message: String,
        privateData: PrivateString,
        category: String = "default",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) async {
        await log(level: .info, message: message, privateData: privateData, category: category, file: file, function: function, line: line)
    }
    
    public func notice(
        _ message: String,
        privateData: PrivateString,
        category: String = "default",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) async {
        await log(level: .notice, message: message, privateData: privateData, category: category, file: file, function: function, line: line)
    }
    
    public func error(
        _ message: String,
        privateData: PrivateString,
        category: String = "default",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) async {
        await log(level: .error, message: message, privateData: privateData, category: category, file: file, function: function, line: line)
    }
    
    public func fault(
        _ message: String,
        privateData: PrivateString,
        category: String = "default",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) async {
        await log(level: .fault, message: message, privateData: privateData, category: category, file: file, function: function, line: line)
    }
    
    public func getLogs(
        levels: Set<LogLevel>? = nil,
        categories: Set<String>? = nil,
        subsystems: Set<String>? = nil,
        from startDate: Date? = nil,
        to endDate: Date? = nil,
        limit: Int? = nil
    ) async throws -> [LogEntry] {
        return try await storage.retrieve(
            levels: levels,
            categories: categories,
            subsystems: subsystems,
            from: startDate,
            to: endDate,
            limit: limit
        )
    }
    
    public func clearLogs() async throws {
        try await storage.clear()
        recentLogs.removeAll()
    }
    
    public func exportLogs(format: ExportFormat = .json) async throws -> Data {
        let logs = try await storage.retrieve(
            levels: nil,
            categories: nil,
            subsystems: nil,
            from: nil,
            to: nil,
            limit: nil
        )
        return try format.encode(logs)
    }
}

public enum ExportFormat {
    case json
    case csv
    case txt
    
    func encode(_ logs: [LogEntry]) throws -> Data {
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
