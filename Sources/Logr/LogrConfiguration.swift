import Foundation

public struct LogrConfiguration: Sendable, Codable {
    public var maxLogEntries: Int
    public var maxLogAge: TimeInterval
    public var enabledLevels: Set<LogLevel>
    public var subsystem: String
    public var cleanupInterval: TimeInterval
    
    public static let `default` = LogrConfiguration(
        maxLogEntries: 10_000,
        maxLogAge: 7 * 24 * 60 * 60,
        enabledLevels: Set(LogLevel.allCases),
        subsystem: Bundle.main.bundleIdentifier ?? "com.logr.default",
        cleanupInterval: 60 * 60
    )
    
    public init(
        maxLogEntries: Int = 10_000,
        maxLogAge: TimeInterval = 7 * 24 * 60 * 60,
        enabledLevels: Set<LogLevel> = Set(LogLevel.allCases),
        subsystem: String = Bundle.main.bundleIdentifier ?? "com.logr.default",
        cleanupInterval: TimeInterval = 60 * 60
    ) {
        self.maxLogEntries = maxLogEntries
        self.maxLogAge = maxLogAge
        self.enabledLevels = enabledLevels
        self.subsystem = subsystem
        self.cleanupInterval = cleanupInterval
    }
    
    public func shouldLog(level: LogLevel) -> Bool {
        enabledLevels.contains(level)
    }
}