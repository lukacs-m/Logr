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
    /// Verbose logging with the source location.
    ///
    /// Output format: `message (file:line function)`; Console already shows the category and level.
    ///
    /// Example: `Button tapped (ContentView.swift:42 viewDidLoad())`
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
/// - **categoryLevelOverrides**: `nil` (no per-category overrides)
/// - **coalesceWindowMillis**: 100 ms notification coalescing
/// - **mirrorToOSLog**: `true`
/// - **storesPrivateValues**: `true` in `DEBUG` builds, `false` otherwise
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
/// ``init(maxLogEntries:maxLogAge:enabledLevels:categoryLevelOverrides:subsystem:cleanupInterval:logVerbosity:coalesceWindowMillis:mirrorToOSLog:storesPrivateValues:)``
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
/// - ``coalesceWindowMillis``
/// - ``mirrorToOSLog``
/// - ``storesPrivateValues``
public struct LogrConfiguration: Sendable, Codable {
    /// Maximum number of log entries to keep in memory and storage.
    ///
    /// When this limit is reached, the oldest entries are removed. Values are clamped to 100...100,000: fewer
    /// would make the viewer and the analysis useless, and more would hold too much in memory, which also sizes
    /// the history read at launch (100,000 is the writer's backpressure cap). Default: 10,000 entries.
    public let maxLogEntries: Int

    static let maxLogEntriesRange = 100...100_000

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
    /// Cleanup removes old entries and enforces entry count limits. Values are clamped to 60...86,400 (one minute
    /// to one day): a pass more often would keep rewriting the storage, and one less often may never run in a
    /// session. NaN means the default. Default: 3,600 seconds (1 hour).
    public let cleanupInterval: TimeInterval

    static let cleanupIntervalRange: ClosedRange<TimeInterval> = 60...86_400

    /// Controls the verbosity of log output.
    ///
    /// - `.verbose`: Includes source file, function, and line number
    /// - `.normal`: Just the log message
    ///
    /// Default: `.verbose`
    public let logVerbosity: LogVerbosity

    /// Minimum interval, in milliseconds, between SwiftUI observation notifications for `recentLogs`.
    ///
    /// `recentLogs` is updated synchronously on every log, so every reader — including reads through
    /// the `any LogRService` existential and `getLogs`/`exportLogs`/`logStatistics` — always sees the
    /// latest entry immediately. This window throttles only how often *observers* (SwiftUI views) are
    /// notified, coalescing a burst of logs into at most one view invalidation per window. It
    /// decouples the redraw rate from the logging rate, keeping the UI responsive under high volume.
    /// A larger value means fewer redraws but more latency before a burst is reflected on screen;
    /// `0` notifies on every log.
    ///
    /// Default: 100 (≈10 notifications per second during a burst).
    public let coalesceWindowMillis: Int

    /// Whether each log is mirrored to Apple's unified logging system (OSLog) synchronously.
    ///
    /// When `true` (the default) every log is also written to OSLog so it appears in Console.app.
    /// High-volume apps that rely on LogR's own persistent store can set this to `false` to avoid the
    /// per-call OSLog cost during bursts.
    ///
    /// Default: `true`.
    public let mirrorToOSLog: Bool

    /// Whether ``LogR`` stores private values in clear, so you can read them while developing.
    ///
    /// When `true`, ``LogPrivacy/private`` values (and ``LogPrivacy/auto`` ones that resolve to private) are
    /// stored as logged, and ``LogEntry/privateRanges`` marks them; exports still replace them unless asked to
    /// keep them. When `false`, they are stored as `<private>` or, with ``LogPrivacy/Mask/hash``,
    /// `<private:3f9a1c2e>`. ``LogPrivacy/sensitive`` values are never stored, whatever this says. The OSLog
    /// mirror always logs private values as private.
    ///
    /// Default: `true` when Logr is compiled with `DEBUG` defined (Xcode's Debug configuration), `false` in
    /// release.
    public let storesPrivateValues: Bool

    /// Creates a new LogR configuration.
    ///
    /// All parameters have sensible defaults. Only specify the values you want to customize.
    ///
    /// - Parameters:
    ///   - maxLogEntries: Maximum log entries to keep, clamped to 100...100,000. Default: 10,000
    ///   - maxLogAge: Maximum age in seconds. Default: 7 days
    ///   - enabledLevels: Which log levels to process. Default: All levels
    ///   - categoryLevelOverrides: Per-category minimum log level overrides. Default: Empty
    ///   - subsystem: OSLog subsystem identifier. Default: Bundle identifier
    ///   - cleanupInterval: Cleanup frequency in seconds, clamped to 60...86,400. Default: 1 hour
    ///   - logVerbosity: Output verbosity. Default: `.verbose`
    ///   - coalesceWindowMillis: Min interval between `recentLogs` publications. Default: 100ms
    ///   - mirrorToOSLog: Mirror each log to OSLog. Default: `true`
    ///   - storesPrivateValues: Store private values in clear. Default: `true` in `DEBUG` builds only
    public init(maxLogEntries: Int = LogrConfiguration.default.maxLogEntries,
                maxLogAge: TimeInterval = LogrConfiguration.default.maxLogAge,
                enabledLevels: Set<LogLevel> = LogrConfiguration.default.enabledLevels,
                categoryLevelOverrides: [LogCategory: LogLevel]? = LogrConfiguration.default
                    .categoryLevelOverrides,
                subsystem: String = LogrConfiguration.default.subsystem,
                cleanupInterval: TimeInterval = LogrConfiguration.default.cleanupInterval,
                logVerbosity: LogVerbosity = LogrConfiguration.default.logVerbosity,
                coalesceWindowMillis: Int = LogrConfiguration.default.coalesceWindowMillis,
                mirrorToOSLog: Bool = LogrConfiguration.default.mirrorToOSLog,
                storesPrivateValues: Bool = LogrConfiguration.default.storesPrivateValues) {
        self.maxLogEntries = maxLogEntries.clamped(to: Self.maxLogEntriesRange)
        self.maxLogAge = maxLogAge
        self.enabledLevels = enabledLevels
        self.categoryLevelOverrides = categoryLevelOverrides
        self.subsystem = subsystem
        self.cleanupInterval = Self.validCleanupInterval(cleanupInterval)
        self.logVerbosity = logVerbosity
        self.coalesceWindowMillis = coalesceWindowMillis
        self.mirrorToOSLog = mirrorToOSLog
        self.storesPrivateValues = storesPrivateValues
    }

    private enum CodingKeys: String, CodingKey {
        case maxLogEntries, maxLogAge, enabledLevels, categoryLevelOverrides
        case subsystem, cleanupInterval, logVerbosity, coalesceWindowMillis, mirrorToOSLog, storesPrivateValues
    }

    /// Forward-compatible decoding: any key absent from the payload falls back to its default
    /// rather than throwing. This keeps configs encoded by an earlier version (which lacks fields
    /// added later, e.g. `coalesceWindowMillis`/`mirrorToOSLog`) decodable, so adding a field stays
    /// a non-breaking change. The synthesized `encode(to:)` continues to write every key.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = LogrConfiguration.default
        maxLogEntries = try (container.decodeIfPresent(Int.self, forKey: .maxLogEntries) ?? defaults.maxLogEntries)
            .clamped(to: Self.maxLogEntriesRange)
        maxLogAge = try container.decodeIfPresent(TimeInterval.self, forKey: .maxLogAge)
            ?? defaults.maxLogAge
        enabledLevels = try container.decodeIfPresent(Set<LogLevel>.self, forKey: .enabledLevels)
            ?? defaults.enabledLevels
        categoryLevelOverrides = try container
            .decodeIfPresent([LogCategory: LogLevel].self, forKey: .categoryLevelOverrides)
            ?? defaults.categoryLevelOverrides
        subsystem = try container.decodeIfPresent(String.self, forKey: .subsystem)
            ?? defaults.subsystem
        let decodedCleanupInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .cleanupInterval)
        cleanupInterval = Self.validCleanupInterval(decodedCleanupInterval ?? defaults.cleanupInterval)
        logVerbosity = try container.decodeIfPresent(LogVerbosity.self, forKey: .logVerbosity)
            ?? defaults.logVerbosity
        coalesceWindowMillis = try container.decodeIfPresent(Int.self, forKey: .coalesceWindowMillis)
            ?? defaults.coalesceWindowMillis
        mirrorToOSLog = try container.decodeIfPresent(Bool.self, forKey: .mirrorToOSLog)
            ?? defaults.mirrorToOSLog
        storesPrivateValues = try container.decodeIfPresent(Bool.self, forKey: .storesPrivateValues)
            ?? defaults.storesPrivateValues
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
    /// - 100 ms notification coalescing
    /// - OSLog mirroring enabled
    /// - Private values stored in clear in `DEBUG` builds only
    public static let `default` = LogrConfiguration(maxLogEntries: 10_000,
                                                    maxLogAge: 7 * 24 * 60 * 60,
                                                    enabledLevels: Set(LogLevel.allCases),
                                                    categoryLevelOverrides: nil,
                                                    subsystem: Bundle.main.bundleIdentifier ?? "com.logr.default",
                                                    cleanupInterval: 60 * 60,
                                                    logVerbosity: .verbose,
                                                    coalesceWindowMillis: 100,
                                                    mirrorToOSLog: true,
                                                    storesPrivateValues: isDebugBuild)

    #if DEBUG
    private static let isDebugBuild = true
    #else
    private static let isDebugBuild = false
    #endif
}

private extension LogrConfiguration {
    /// NaN lies in no range, so it gets the default hour (written out: `default` is built through this).
    static func validCleanupInterval(_ interval: TimeInterval) -> TimeInterval {
        interval.isNaN ? 60 * 60 : interval.clamped(to: cleanupIntervalRange)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
