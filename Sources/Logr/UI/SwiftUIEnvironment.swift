//import SwiftUI
//
//// MARK: - Environment Key and Values
//
//public struct LogRServiceEnvironmentKey: @preconcurrency EnvironmentKey {
//    @MainActor
//    public static let defaultValue: LogRService = LogR()
//}
//
//public extension EnvironmentValues {
//    @MainActor
//    var logService: any LogRService {
//        get { self[LogRServiceEnvironmentKey.self] }
//        set { self[LogRServiceEnvironmentKey.self] = newValue }
//    }
//}
//
////extension EnvironmentValues {
////    @Entry var logService: LogRService = 
////}
//
//
//
////struct HomeViewModelKey: EnvironmentKey {
////    @MainActor
////    static var defaultValue: any LogRService = LogR()
////}
////
////extension EnvironmentValues {
////    @MainActor
////    var homeViewModel: HomeView.ViewModel {
////        get { self[HomeViewModelKey.self] }
////        set { self[HomeViewModelKey.self] = newValue }
////    }
////}
//
//// MARK: - View Modifier
//
////public struct LogRServiceModifier: ViewModifier {
////    let service: LogRService
////    
////    public func body(content: Content) -> some View {
////        content
////            .environment(\.logr, service)
////    }
////}
//
//public struct LogRServiceModifier: ViewModifier {
//    let service: LogRService
//    
//    public func body(content: Content) -> some View {
//        content
//            .environment(\.logService, service)
//    }
//}
//    
//extension View {
//    /// Injects a LogRService into the SwiftUI environment
//    func logRService(_ service: LogRService) -> some View {
//        modifier(LogRServiceModifier(service: service))
//    }
//}
//
//// MARK: - Mock Implementation
//
//@Observable
//@MainActor
//public final class MockLogR: LogRService, Sendable {
//    public private(set) var recentLogs: [LogEntry] = []
//    public private(set) var isCleanupRunning = false
//    
//    private var mockLogs: [LogEntry] = []
//    
//    public init() {
//        generateMockData()
//    }
//    
//    private func generateMockData() {
//        let mockEntries: [LogEntry] = [
//            LogEntry(
//                timestamp: Date().addingTimeInterval(-300),
//                level: .info,
//                category: .system,
//                subsystem: "com.logr.example",
//                message: "Application launched successfully"
//            ),
//            LogEntry(
//                timestamp: Date().addingTimeInterval(-240),
//                level: .debug,
//                category: .network,
//                subsystem: "com.logr.example",
//                message: "Network request initiated to api.example.com"
//            ),
//            LogEntry(
//                timestamp: Date().addingTimeInterval(-180),
//                level: .notice,
//                category: .ui,
//                subsystem: "com.logr.example",
//                message: "Main view controller loaded"
//            ),
//            LogEntry(
//                timestamp: Date().addingTimeInterval(-120),
//                level: .error,
//                category: .authentication,
//                subsystem: "com.logr.example",
//                message: "Failed to authenticate user - invalid credentials"
//            ),
//            LogEntry(
//                timestamp: Date().addingTimeInterval(-60),
//                level: .fault,
//                category: .database,
//                subsystem: "com.logr.example",
//                message: "Critical database connection error - attempting recovery"
//            ),
//            LogEntry(
//                timestamp: Date().addingTimeInterval(-30),
//                level: .info,
//                category: .custom("business-logic"),
//                subsystem: "com.logr.example",
//                message: "Order processing completed for order #12345"
//            ),
//            LogEntry(
//                timestamp: Date(),
//                level: .debug,
//                category: .performance,
//                subsystem: "com.logr.example",
//                message: "Memory usage: 45MB, CPU: 12%"
//            )
//        ]
//        
//        mockLogs = mockEntries
//        recentLogs = mockEntries
//    }
//    
//    // MARK: - LogRService Implementation
//    
//    public func log(
//        level: LogLevel,
//        message: String,
//        category: LogCategory,
//        file: String = #file,
//        function: String = #function,
//        line: Int = #line
//    ) {
//        let entry = LogEntry(
//            level: level,
//            category: category,
//            subsystem: "com.logr.mock",
//            message: message,
//            file: file,
//            function: function,
//            line: line
//        )
//        
//        mockLogs.insert(entry, at: 0)
//        recentLogs.insert(entry, at: 0)
//        
//        // Keep only the most recent 100 entries for demo
//        if mockLogs.count > 100 {
//            mockLogs.removeLast()
//        }
//        if recentLogs.count > 100 {
//            recentLogs.removeLast()
//        }
//    }
//    
////    public func log(
////        level: LogLevel,
////        message: String,
////        privateData: PrivateString,
////        category: LogCategory,
////        file: String = #file,
////        function: String = #function,
////        line: Int = #line
////    ) async {
////        let fullMessage = "\(message) \(privateData.redacted)"
////        await log(level: level, message: fullMessage, category: category, file: file, function: function, line: line)
////    }
//    
//    public func debug(
//        _ message: String,
//        category: LogCategory,
//        file: String = #file,
//        function: String = #function,
//        line: Int = #line
//    ) async {
//         log(level: .debug, message: message, category: category, file: file, function: function, line: line)
//    }
//    
//    public func info(
//        _ message: String,
//        category: LogCategory,
//        file: String = #file,
//        function: String = #function,
//        line: Int = #line
//    ) async {
//         log(level: .info, message: message, category: category, file: file, function: function, line: line)
//    }
//    
//    public func notice(
//        _ message: String,
//        category: LogCategory,
//        file: String = #file,
//        function: String = #function,
//        line: Int = #line
//    ) async {
//         log(level: .notice, message: message, category: category, file: file, function: function, line: line)
//    }
//    
//    public func error(
//        _ message: String,
//        category: LogCategory,
//        file: String = #file,
//        function: String = #function,
//        line: Int = #line
//    ) async {
//         log(level: .error, message: message, category: category, file: file, function: function, line: line)
//    }
//    
//    public func fault(
//        _ message: String,
//        category: LogCategory,
//        file: String = #file,
//        function: String = #function,
//        line: Int = #line
//    ) async {
//         log(level: .fault, message: message, category: category, file: file, function: function, line: line)
//    }
//    
////    public func debug(
////        _ message: String,
////        privateData: PrivateString,
////        category: LogCategory,
////        file: String = #file,
////        function: String = #function,
////        line: Int = #line
////    ) async {
////        await log(level: .debug, message: message, privateData: privateData, category: category, file: file, function: function, line: line)
////    }
////    
////    public func info(
////        _ message: String,
////        privateData: PrivateString,
////        category: LogCategory,
////        file: String = #file,
////        function: String = #function,
////        line: Int = #line
////    ) async {
////        await log(level: .info, message: message, privateData: privateData, category: category, file: file, function: function, line: line)
////    }
////    
////    public func notice(
////        _ message: String,
////        privateData: PrivateString,
////        category: LogCategory,
////        file: String = #file,
////        function: String = #function,
////        line: Int = #line
////    ) async {
////        await log(level: .notice, message: message, privateData: privateData, category: category, file: file, function: function, line: line)
////    }
////    
////    public func error(
////        _ message: String,
////        privateData: PrivateString,
////        category: LogCategory,
////        file: String = #file,
////        function: String = #function,
////        line: Int = #line
////    ) async {
////        await log(level: .error, message: message, privateData: privateData, category: category, file: file, function: function, line: line)
////    }
////    
////    public func fault(
////        _ message: String,
////        privateData: PrivateString,
////        category: LogCategory,
////        file: String = #file,
////        function: String = #function,
////        line: Int = #line
////    ) async {
////        await log(level: .fault, message: message, privateData: privateData, category: category, file: file, function: function, line: line)
////    }
//    
//    public func getLogs(
//        levels: Set<LogLevel>? = nil,
//        categories: Set<LogCategory>? = nil,
//        subsystems: Set<String>? = nil,
//        from startDate: Date? = nil,
//        to endDate: Date? = nil,
//        limit: Int? = nil
//    ) async throws -> [LogEntry] {
//        var filtered = mockLogs
//        
//        if let levels = levels {
//            filtered = filtered.filter { levels.contains($0.level) }
//        }
//        
//        if let categories = categories {
//            filtered = filtered.filter { categories.contains($0.category) }
//        }
//        
//        if let subsystems = subsystems {
//            filtered = filtered.filter { subsystems.contains($0.subsystem) }
//        }
//        
//        if let startDate = startDate {
//            filtered = filtered.filter { $0.timestamp >= startDate }
//        }
//        
//        if let endDate = endDate {
//            filtered = filtered.filter { $0.timestamp <= endDate }
//        }
//        
//        filtered.sort { $0.timestamp > $1.timestamp }
//        
//        if let limit = limit {
//            filtered = Array(filtered.prefix(limit))
//        }
//        
//        return filtered
//    }
//    
//    public func clearLogs() async throws {
//        mockLogs.removeAll()
//        recentLogs.removeAll()
//    }
//    
//    public func exportLogs(format: ExportFormat = .json) async throws -> Data {
//        return try format.encode(mockLogs)
//    }
//}
