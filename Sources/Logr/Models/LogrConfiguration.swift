//
//  LogrConfiguration.swift
//  Logr
//
//  Created by martin on 02/11/2025.
//

import Foundation

/// Controls the amount of detail in logged messages.
///
/// ## Cases
///
/// - **verbose**: Includes file name, function name, and line number in logs
/// - **normal**: Only includes the log message without source location details
public enum LogVerbosity: Sendable, Equatable, Codable {
    /// Verbose logging with full source location details.
    ///
    /// Output format: `[category][level] message (file:function:line)`
    ///
    /// Example: `[ui][info] Button tapped (ContentView.swift:viewDidLoad():42)`
    case verbose

    /// Normal logging with just the message.
    ///
    /// Output format: `message`
    ///
    /// Example: `Button tapped`
    case normal
}

/// Configuration options for customizing LogR behavior.
///
/// `LogrConfiguration` controls various aspects of the logging system including
/// retention policies, cleanup intervals, enabled log levels, and output verbosity.
///
/// ## Overview
///
/// Configure LogR at initialization with custom settings, or use the sensible
/// defaults for most common use cases.
///
/// ## Default Configuration
///
/// The default configuration provides:
/// - **maxLogEntries**: 10,000 entries
/// - **maxLogAge**: 7 days (604,800 seconds)
/// - **enabledLevels**: All log levels
/// - **subsystem**: Your app's bundle identifier
/// - **cleanupInterval**: 1 hour (3,600 seconds)
/// - **logVerbosity**: Verbose (with source location)
///
/// ## Example
///
/// ```swift
/// // Use default configuration
/// let logger = LogR()
///
/// // Custom configuration for production
/// let config = LogrConfiguration(
///     maxLogEntries: 5_000,
///     maxLogAge: 24 * 60 * 60,  // 1 day
///     enabledLevels: [.info, .warning, .error, .fault],
///     subsystem: "com.myapp.logging",
///     cleanupInterval: 30 * 60,  // 30 minutes
///     logVerbosity: .normal
/// )
/// let logger = LogR(configuration: config)
/// ```
///
/// ## Topics
///
/// ### Creating Configuration
/// -
/// ``init(maxLogEntries:maxLogAge:enabledLevels:categoryLevelOverrides:subsystem:cleanupInterval:logVerbosity:)``
/// - ``default``
///
/// ### Properties
/// - ``maxLogEntries``
/// - ``maxLogAge``
/// - ``enabledLevels``
/// - ``categoryLevelOverrides``
/// - ``subsystem``
/// - ``cleanupInterval``
/// - ``logVerbosity``
public struct LogrConfiguration: Sendable, Codable {
    /// Maximum number of log entries to keep in memory and storage.
    ///
    /// When this limit is reached, the oldest entries are removed.
    /// Default: 10,000 entries.
    public let maxLogEntries: Int

    /// Maximum age of log entries in seconds before cleanup.
    ///
    /// Entries older than this are automatically deleted during cleanup cycles.
    /// Default: 604,800 seconds (7 days).
    public let maxLogAge: TimeInterval

    /// Set of log levels that should be processed.
    ///
    /// Logs with levels not in this set are ignored. This allows you to
    /// disable debug logs in production, for example.
    /// Default: All levels enabled.
    ///
    /// ## Example
    /// ```swift
    /// // Only log errors and faults in production
    /// let config = LogrConfiguration(
    ///     enabledLevels: [.error, .fault]
    /// )
    /// ```
    public let enabledLevels: Set<LogLevel>

    /// Per-category minimum log level overrides.
    ///
    /// Allows fine-grained control over which log levels are enabled
    /// for specific categories. When a category has an override, only
    /// logs at or above the specified level will be processed.
    ///
    /// This takes precedence over `enabledLevels` for matching categories.
    ///
    /// ## Example
    /// ```swift
    /// let config = LogrConfiguration(
    ///     enabledLevels: [.warning, .error, .fault],
    ///     categoryLevelOverrides: [
    ///         .network: .debug,     // Verbose network logging
    ///         .ui: .error           // Only errors for UI
    ///     ]
    /// )
    /// ```
    public let categoryLevelOverrides: [LogCategory: LogLevel]?

    /// OSLog subsystem identifier for this logger.
    ///
    /// Typically your app's bundle identifier. This appears in Console.app
    /// and helps filter logs system-wide.
    /// Default: `Bundle.main.bundleIdentifier` or "com.logr.default"
    public let subsystem: String

    /// Time interval between automatic cleanup operations in seconds.
    ///
    /// Cleanup removes old entries and enforces entry count limits.
    /// Default: 3,600 seconds (1 hour).
    public let cleanupInterval: TimeInterval

    /// Controls the verbosity of log output.
    ///
    /// - `.verbose`: Includes source file, function, and line number
    /// - `.normal`: Just the log message
    ///
    /// Default: `.verbose`
    public let logVerbosity: LogVerbosity

    /// Creates a new LogR configuration.
    ///
    /// All parameters have sensible defaults. Only specify the values you want to customize.
    ///
    /// - Parameters:
    ///   - maxLogEntries: Maximum log entries to keep. Default: 10,000
    ///   - maxLogAge: Maximum age in seconds. Default: 7 days
    ///   - enabledLevels: Which log levels to process. Default: All levels
    ///   - categoryLevelOverrides: Per-category minimum log level overrides. Default: Empty
    ///   - subsystem: OSLog subsystem identifier. Default: Bundle identifier
    ///   - cleanupInterval: Cleanup frequency in seconds. Default: 1 hour
    ///   - logVerbosity: Output verbosity. Default: `.verbose`
    public init(maxLogEntries: Int = LogrConfiguration.default.maxLogEntries,
                maxLogAge: TimeInterval = LogrConfiguration.default.maxLogAge,
                enabledLevels: Set<LogLevel> = LogrConfiguration.default.enabledLevels,
                categoryLevelOverrides: [LogCategory: LogLevel]? = LogrConfiguration.default
                    .categoryLevelOverrides,
                subsystem: String = LogrConfiguration.default.subsystem,
                cleanupInterval: TimeInterval = LogrConfiguration.default.cleanupInterval,
                logVerbosity: LogVerbosity = LogrConfiguration.default.logVerbosity) {
        self.maxLogEntries = maxLogEntries
        self.maxLogAge = maxLogAge
        self.enabledLevels = enabledLevels
        self.categoryLevelOverrides = categoryLevelOverrides
        self.subsystem = subsystem
        self.cleanupInterval = cleanupInterval
        self.logVerbosity = logVerbosity
    }

    /// Default configuration with sensible values for most applications.
    ///
    /// Provides:
    /// - 10,000 max log entries
    /// - 7 day retention
    /// - All log levels enabled
    /// - No per-category overrides
    /// - Bundle identifier as subsystem
    /// - 1 hour cleanup interval
    /// - Verbose output with source locations
    public static let `default` = LogrConfiguration(maxLogEntries: 10_000,
                                                    maxLogAge: 7 * 24 * 60 * 60,
                                                    enabledLevels: Set(LogLevel.allCases),
                                                    categoryLevelOverrides: nil,
                                                    subsystem: Bundle.main.bundleIdentifier ?? "com.logr.default",
                                                    cleanupInterval: 60 * 60,
                                                    logVerbosity: .verbose)
}
