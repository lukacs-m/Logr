import Foundation

public enum LogVerbosity: Sendable, Equatable, Codable {
    case verbose
    case normal
}

public struct LogrConfiguration: Sendable, Codable {
    public let maxLogEntries: Int
    public let maxLogAge: TimeInterval
    public let enabledLevels: Set<LogLevel>
    public let subsystem: String
    public let cleanupInterval: TimeInterval
    public let logVerbosity: LogVerbosity

    public init(maxLogEntries: Int = LogrConfiguration.default.maxLogEntries,
                maxLogAge: TimeInterval = LogrConfiguration.default.maxLogAge,
                enabledLevels: Set<LogLevel> = LogrConfiguration.default.enabledLevels,
                subsystem: String = LogrConfiguration.default.subsystem,
                cleanupInterval: TimeInterval = LogrConfiguration.default.cleanupInterval,
                logVerbosity: LogVerbosity = LogrConfiguration.default.logVerbosity) {
        self.maxLogEntries = maxLogEntries
        self.maxLogAge = maxLogAge
        self.enabledLevels = enabledLevels
        self.subsystem = subsystem
        self.cleanupInterval = cleanupInterval
        self.logVerbosity = logVerbosity
    }

    public static let `default` = LogrConfiguration(maxLogEntries: 10_000,
                                                    maxLogAge: 7 * 24 * 60 * 60,
                                                    enabledLevels: Set(LogLevel.allCases),
                                                    subsystem: Bundle.main.bundleIdentifier ?? "com.logr.default",
                                                    cleanupInterval: 60 * 60,
                                                    logVerbosity: .verbose)
}
