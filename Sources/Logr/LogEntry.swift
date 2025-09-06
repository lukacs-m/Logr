import Foundation
import OSLog

@frozen
public struct LogEntry: Sendable, Codable, Identifiable, Hashable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let category: String
    public let subsystem: String
    public let message: String
    public let file: String
    public let function: String
    public let line: Int
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: LogLevel,
        category: String,
        subsystem: String,
        message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.subsystem = subsystem
        self.message = message
        self.file = file
        self.function = function
        self.line = line
    }
}

@frozen
public enum LogLevel: String, CaseIterable, Sendable, Codable {
    case debug
    case info
    case notice
    case error
    case fault
    
    public var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .notice: return .default
        case .error: return .error
        case .fault: return .fault
        }
    }
    
    public var displayName: String {
        switch self {
        case .debug: return "Debug"
        case .info: return "Info"
        case .notice: return "Notice"
        case .error: return "Error"
        case .fault: return "Fault"
        }
    }
    
    public var priority: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .notice: return 2
        case .error: return 3
        case .fault: return 4
        }
    }
}