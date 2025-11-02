//import Foundation
//import Observation
//
//@MainActor
//public protocol LogRService: Observable {
//    var recentLogs: [LogEntry] { get }
//    
//    // Core logging methods
//    func log(
//        level: LogLevel,
//        message: String,
//        category: LogCategory,
//        file: String,
//        function: String,
//        line: Int
//    ) async
//    
//    func log(
//        level: LogLevel,
//        message: String,
//        privateData: PrivateString,
//        category: LogCategory,
//        file: String,
//        function: String,
//        line: Int
//    ) async
//    
//    // Convenience methods for each log level
//    func debug(
//        _ message: String,
//        category: LogCategory,
//        file: String,
//        function: String,
//        line: Int
//    ) async
//    
//    func info(
//        _ message: String,
//        category: LogCategory,
//        file: String,
//        function: String,
//        line: Int
//    ) async
//    
//    func notice(
//        _ message: String,
//        category: LogCategory,
//        file: String,
//        function: String,
//        line: Int
//    ) async
//    
//    func error(
//        _ message: String,
//        category: LogCategory,
//        file: String,
//        function: String,
//        line: Int
//    ) async
//    
//    func fault(
//        _ message: String,
//        category: LogCategory,
//        file: String,
//        function: String,
//        line: Int
//    ) async
//    
//    // Convenience methods with private data
//    func debug(
//        _ message: String,
//        privateData: PrivateString,
//        category: LogCategory,
//        file: String,
//        function: String,
//        line: Int
//    ) async
//    
//    func info(
//        _ message: String,
//        privateData: PrivateString,
//        category: LogCategory,
//        file: String,
//        function: String,
//        line: Int
//    ) async
//    
//    func notice(
//        _ message: String,
//        privateData: PrivateString,
//        category: LogCategory,
//        file: String,
//        function: String,
//        line: Int
//    ) async
//    
//    func error(
//        _ message: String,
//        privateData: PrivateString,
//        category: LogCategory,
//        file: String,
//        function: String,
//        line: Int
//    ) async
//    
//    func fault(
//        _ message: String,
//        privateData: PrivateString,
//        category: LogCategory,
//        file: String,
//        function: String,
//        line: Int
//    ) async
//    
//    // Query and management methods
//    func getLogs(
//        levels: Set<LogLevel>?,
//        categories: Set<LogCategory>?,
//        subsystems: Set<String>?,
//        from startDate: Date?,
//        to endDate: Date?,
//        limit: Int?
//    ) async throws -> [LogEntry]
//    
//    func clearLogs() async throws
//    func exportLogs(format: ExportFormat) async throws -> Data
//}

// Default implementations for convenience methods
//public extension LogRService {
//    func debug(
//        _ message: String,
//        category: LogCategory = .debug,
//        file: String = #file,
//        function: String = #function,
//        line: Int = #line
//    ) async {
//        await self.debug(message, category: category, file: file, function: function, line: line)
//    }
//    
//    func info(
//        _ message: String,
//        category: LogCategory = .system,
//        file: String = #file,
//        function: String = #function,
//        line: Int = #line
//    ) async {
//        await self.info(message, category: category, file: file, function: function, line: line)
//    }
//    
//    func notice(
//        _ message: String,
//        category: LogCategory = .system,
//        file: String = #file,
//        function: String = #function,
//        line: Int = #line
//    ) async {
//        await self.notice(message, category: category, file: file, function: function, line: line)
//    }
//    
//    func error(
//        _ message: String,
//        category: LogCategory = .system,
//        file: String = #file,
//        function: String = #function,
//        line: Int = #line
//    ) async {
//        await self.error(message, category: category, file: file, function: function, line: line)
//    }
//    
//    func fault(
//        _ message: String,
//        category: LogCategory = .system,
//        file: String = #file,
//        function: String = #function,
//        line: Int = #line
//    ) async {
//        await self.fault(message, category: category, file: file, function: function, line: line)
//    }
    
//    func debug(
//        _ message: String,
//        privateData: PrivateString,
//        category: LogCategory = .debug,
//        file: String = #file,
//        function: String = #function,
//        line: Int = #line
//    ) async {
//        await self.debug(message, privateData: privateData, category: category, file: file, function: function, line: line)
//    }
//    
//    func info(
//        _ message: String,
//        privateData: PrivateString,
//        category: LogCategory = .system,
//        file: String = #file,
//        function: String = #function,
//        line: Int = #line
//    ) async {
//        await self.info(message, privateData: privateData, category: category, file: file, function: function, line: line)
//    }
//    
//    func notice(
//        _ message: String,
//        privateData: PrivateString,
//        category: LogCategory = .system,
//        file: String = #file,
//        function: String = #function,
//        line: Int = #line
//    ) async {
//        await self.notice(message, privateData: privateData, category: category, file: file, function: function, line: line)
//    }
//    
//    func error(
//        _ message: String,
//        privateData: PrivateString,
//        category: LogCategory = .system,
//        file: String = #file,
//        function: String = #function,
//        line: Int = #line
//    ) async {
//        await self.error(message, privateData: privateData, category: category, file: file, function: function, line: line)
//    }
//    
//    func fault(
//        _ message: String,
//        privateData: PrivateString,
//        category: LogCategory = .system,
//        file: String = #file,
//        function: String = #function,
//        line: Int = #line
//    ) async {
//        await self.fault(message, privateData: privateData, category: category, file: file, function: function, line: line)
//    }
//}
