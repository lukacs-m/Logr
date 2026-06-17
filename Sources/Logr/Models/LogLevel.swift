//
//  LogLevel.swift
//  Logr
//
//  Created by martin on 14/09/2025.
//

import Foundation
import OSLog

/// Severity levels for log messages, from debug information to critical faults.
///
/// `LogLevel` defines six levels of log severity, aligned with Apple's OSLog levels.
/// Each level represents a different degree of importance and urgency.
///
/// ## Overview
///
/// The log levels, from least to most severe:
///
/// 1. **debug**: Detailed information for development and debugging
/// 2. **info**: General informational messages about app state
/// 3. **notice**: Significant events that are expected and user-visible
/// 4. **warning**: Unexpected non-fatal conditions
/// 5. **error**: Significant problems preventing specific operations
/// 6. **fault**: Critical system-level errors requiring immediate attention
///
/// ## Best Practices
///
/// - Use `.debug` for detailed troubleshooting information (disable in production)
/// - Use `.info` for tracking normal app flow and operations
/// - Use `.notice` for significant but expected events
/// - Use `.warning` for unexpected but recoverable conditions
/// - Use `.error` for failures that affect specific features
/// - Use `.fault` for critical errors that may cause instability
///
/// ## Example
///
/// ```swift
/// logger.debug("Cache hit: \(key)", category: .cache)
/// logger.info("User logged in", category: .authentication)
/// logger.warning("API response slow", category: .network)
/// logger.error("Failed to load data", category: .database)
/// logger.fault("Critical database error", category: .database)
/// ```
///
/// ## Topics
///
/// ### Cases
/// - ``debug``
/// - ``info``
/// - ``notice``
/// - ``warning``
/// - ``error``
/// - ``fault``
///
/// ### Properties
/// - ``osLogType``
/// - ``displayName``
/// - ``priority``
/// - ``visualCue``
public enum LogLevel: String, CaseIterable, Sendable, Codable, Hashable, Identifiable, Equatable {
    /// Debug-level messages for development and active debugging.
    ///
    /// Debug logs contain detailed information useful during development.
    /// These should typically be disabled in production builds.
    case debug

    /// Informational messages about normal app operations.
    ///
    /// Info logs capture general information that may be helpful for
    /// troubleshooting but isn't critical. Use for high-level system events
    /// like startup, configuration, or state changes.
    case info

    /// Notice-level messages for user-visible, expected events.
    ///
    /// Notice logs mark significant events that are normal and expected,
    /// but more important than general information.
    case notice

    /// Warning-level messages for unexpected non-fatal failures.
    ///
    /// Warning logs indicate unexpected conditions that don't prevent the app
    /// from functioning but should be investigated. Non-critical recoverable issues.
    case warning

    /// Error-level messages for significant runtime errors.
    ///
    /// Error logs report critical errors and failures that prevent specific
    /// operations from completing, but don't halt the entire application.
    case error

    /// Fault-level messages for system-level or critical errors.
    ///
    /// Fault logs capture critical errors that may cause the app to behave
    /// incorrectly or crash. Reserved for invariant violations and programming bugs.
    case fault

    /// The corresponding OSLog type for this log level.
    ///
    /// Maps LogR levels to Apple's `OSLogType` for native logging support.
    public var osLogType: OSLogType {
        switch self {
        case .debug: .debug
        case .info: .info
        case .notice: .info
        case .warning: .default
        case .error: .error
        case .fault: .fault
        }
    }

    /// A human-readable name for this log level.
    ///
    /// Used in UI and exported logs for display purposes.
    public var displayName: String {
        switch self {
        case .debug: "Debug"
        case .info: "Info"
        case .notice: "Notice"
        case .warning: "Warning"
        case .error: "Error"
        case .fault: "Fault"
        }
    }

    /// Numeric priority for sorting and filtering (0 = lowest, 5 = highest).
    ///
    /// Higher priority levels indicate more severe issues:
    /// - debug: 0
    /// - info: 1
    /// - notice: 2
    /// - warning: 3
    /// - error: 4
    /// - fault: 5
    public var priority: Int {
        switch self {
        case .debug: 0
        case .info: 1
        case .notice: 2
        case .warning: 3
        case .error: 4
        case .fault: 5
        }
    }

    /// Visual indicator emoji for this log level.
    ///
    /// Provides a quick visual cue in UIs:
    /// - debug: 🟣 (purple)
    /// - info/notice: 🔵 (blue)
    /// - warning: 🟡 (yellow)
    /// - error/fault: 🔴 (red)
    public var visualCue: String {
        switch self {
        case .debug: "🟣"
        case .info, .notice: "🔵"
        case .warning: "🟡"
        case .error, .fault: "🔴"
        }
    }

    /// Conformance to `Identifiable` for SwiftUI list rendering.
    public var id: Self { self }
}
