//
//  LogRService.swift
//  Logr
//
//  Created by Martin Lukacs on 16/11/2025.
//

import Collections
import Foundation

/// The main logging service protocol that defines all logging operations.
///
/// `LogRService` provides a comprehensive interface for logging messages with various
/// severity levels, managing log storage, exporting logs, and performing AI-powered analysis.
///
/// ## Overview
///
/// The service maintains an in-memory cache of recent logs and optionally persists them
/// to storage with automatic encryption. All operations are `@MainActor` isolated for
/// thread safety and SwiftUI integration.
///
/// ## Example Usage
///
/// ```swift
/// import Logr
/// import SwiftUI
///
/// @main
/// struct MyApp: App {
///     let logger = LogR()
///
///     var body: some Scene {
///         WindowGroup {
///             ContentView()
///                 .logRService(logger)
///         }
///     }
/// }
///
/// struct ContentView: View {
///     @Environment(\.logr) private var logger
///
///     var body: some View {
///         Button("Test") {
///             logger.info("Button tapped", category: .ui)
///         }
///     }
/// }
/// ```
///
/// ## Topics
///
/// ### State Properties
/// - ``recentLogs``
/// - ``canAnalyseLogs``
/// - ``privacyAnalysisResult``
/// - ``logIssueSummary``
///
/// ### Core Logging
/// - ``log(level:message:category:file:function:line:metadata:)``
/// - ``debug(_:category:file:function:line:metadata:)``
/// - ``info(_:category:file:function:line:metadata:)``
/// - ``notice(_:category:file:function:line:metadata:)``
/// - ``warning(_:category:file:function:line:metadata:)``
/// - ``error(_:category:file:function:line:metadata:)``
/// - ``fault(_:category:file:function:line:metadata:)``
///
/// ### Log Management
/// - ``exportLogs(format:)``
/// - ``clearLogs()``
/// - ``flush()``
///
/// ### AI Analysis
/// - ``scanForPrivacyIssues()``
/// - ``summarizeIssues()``
@MainActor
public protocol LogRService: Observable, Sendable {
    /// Recent logs maintained in memory for quick access.
    ///
    /// This array contains the most recent log entries, up to the configured `maxLogEntries` limit.
    /// The logs are automatically updated as new entries are added and old entries are cleaned up.
    ///
    /// - Note: This is an in-memory cache. For persistent storage, configure a storage backend.
    var recentLogs: Deque<LogEntry> { get }

    /// Indicates whether AI analysis features are available.
    ///
    /// This property returns `true` when running on iOS 26+ or macOS 26+ with an AI analyzer configured.
    /// When `false`, calling `scanForPrivacyIssues()` or `summarizeIssues()` will throw an error.
    var canAnalyseLogs: Bool { get }

    /// The most recent privacy analysis result (iOS 26+).
    ///
    /// Contains warnings about potential privacy issues detected in logs, along with
    /// a privacy score and recommendations for improvement.
    ///
    /// - Requires: iOS 26.0, macOS 26.0, tvOS 26.0, or watchOS 12.0
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    var privacyAnalysisResult: PrivacyAnalysisResult? { get }

    /// The most recent AI-generated issue summary (iOS 26+).
    ///
    /// Provides an intelligent summary of critical issues found in logs, including
    /// key problems, recommendations, and affected categories.
    ///
    /// - Requires: iOS 26.0, macOS 26.0, tvOS 26.0, or watchOS 12.0
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    var logIssueSummary: LogIssueSummary? { get }

    /// The current progress of an ongoing AI analysis operation (iOS 26+).
    ///
    /// This property is updated in real-time during analysis operations and can be
    /// observed in SwiftUI views to display progress indicators.
    ///
    /// - Requires: iOS 26.0, macOS 26.0, tvOS 26.0, or watchOS 12.0
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    var analysisProgress: AnalysisProgress? { get }

    /// Logs a message with the specified level, category, and source information.
    ///
    /// This is the core logging method that all convenience methods delegate to.
    /// The message is logged to OSLog and optionally persisted to storage with encryption.
    ///
    /// - Parameters:
    ///   - level: The severity level of the log message.
    ///   - message: The message to log. Uses `@autoclosure` for lazy evaluation.
    ///   - category: The category for organizing and filtering logs.
    ///   - file: The source file (automatically captured).
    ///   - function: The function name (automatically captured).
    ///   - line: The line number (automatically captured).
    ///   - metadata: Optional structured key-value metadata for the log entry.
    ///
    /// - Note: The message is only evaluated if the log level is enabled in the configuration.
    func log(level: LogLevel,
             message: @autoclosure () -> String,
             category: LogCategory,
             file: String,
             function: String,
             line: Int,
             metadata: [String: LogMetadataValue]?)

    /// Exports all recent logs in the specified format.
    ///
    /// - Parameter format: The export format (`.json`, `.csv`, or `.txt`).
    /// - Returns: The exported data, or `nil` if there are no logs to export.
    ///
    /// ## Example
    /// ```swift
    /// if let jsonData = logger.exportLogs(format: .json) {
    ///     try? jsonData.write(to: fileURL)
    /// }
    /// ```
    func exportLogs(format: ExportFormat) -> Data?

    func logStatistics() -> LogStatistics

    /// Clears all logs from both memory and persistent storage.
    ///
    /// - Throws: Storage-related errors if the operation fails.
    ///
    /// ## Example
    /// ```swift
    /// Task {
    ///     try await logger.clearLogs()
    /// }
    /// ```
    func clearLogs() async throws

    /// Flushes any pending log entries to persistent storage.
    ///
    /// This ensures that all queued log entries are written to storage immediately,
    /// rather than waiting for the normal background write cycle.
    ///
    /// - Note: Useful before app termination or when you need to guarantee persistence.
    func flush() async

    /// Scans logs for potential privacy issues using AI analysis (iOS 26+).
    ///
    /// Analyzes recent logs to detect potential privacy violations, sensitive data exposure,
    /// and compliance issues. Returns a detailed analysis with warnings and recommendations.
    ///
    /// - Returns: A `PrivacyAnalysisResult` containing warnings, privacy score, and recommendations.
    /// - Throws: `AIAnalyzerError` if AI analysis is unavailable or fails.
    ///
    /// - Requires: iOS 26.0, macOS 26.0, tvOS 26.0, or watchOS 12.0
    ///
    /// ## Example
    /// ```swift
    /// if #available(iOS 26.0, *) {
    ///     Task {
    ///         let result = try await logger.scanForPrivacyIssues()
    ///         print("Privacy Score: \(result.privacyScore)")
    ///         for warning in result.warnings {
    ///             print("⚠️ \(warning.message)")
    ///         }
    ///     }
    /// }
    /// ```
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    @discardableResult func scanForPrivacyIssues() async throws -> PrivacyAnalysisResult

    /// Generates an AI-powered summary of critical issues in logs (iOS 26+).
    ///
    /// Uses AI to analyze error and warning logs, identify patterns, and provide
    /// actionable recommendations for addressing issues.
    ///
    /// - Returns: A `LogIssueSummary` with key issues, recommendations, and affected categories.
    /// - Throws: `AIAnalyzerError` if AI analysis is unavailable or fails.
    ///
    /// - Requires: iOS 26.0, macOS 26.0, tvOS 26.0, or watchOS 12.0
    ///
    /// ## Example
    /// ```swift
    /// if #available(iOS 26.0, *) {
    ///     Task {
    ///         let summary = try await logger.summarizeIssues()
    ///         print("Summary: \(summary.summary)")
    ///         for issue in summary.keyIssues {
    ///             print("- \(issue)")
    ///         }
    ///     }
    /// }
    /// ```
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    @discardableResult func summarizeIssues() async throws -> LogIssueSummary
}

// MARK: - Utils implementations

public extension LogRService {
    func log(level: LogLevel,
             message: @autoclosure () -> String,
             category: LogCategory,
             file: String = #file,
             function: String = #function,
             line: Int = #line,
             metadata: [String: LogMetadataValue]? = nil) {
        log(level: level, message: message(), category: category, file: file, function: function, line: line,
            metadata: metadata)
    }

    func getLogs(levels: Set<LogLevel>? = nil,
                 categories: Set<LogCategory>? = nil,
                 subsystems: Set<String>? = nil,
                 from startDate: Date? = nil,
                 to endDate: Date? = nil,
                 limit: Int? = nil) throws -> [LogEntry] {
        guard !recentLogs.isEmpty else {
            return []
        }

        let filteredLogs = recentLogs.lazy.filter { entry in
            if let levels, !levels.contains(entry.level) { return false }
            if let categories, !categories.contains(entry.category) { return false }
            if let subsystems, !subsystems.contains(entry.subsystem) { return false }
            if let startDate, entry.timestamp < startDate { return false }
            if let endDate, entry.timestamp > endDate { return false }
            return true
        }
        if let limit {
            return Array(filteredLogs.prefix(limit))
        }
        return Array(filteredLogs)
    }

    func exportLogs(format: ExportFormat = .json) -> Data? {
        guard !recentLogs.isEmpty else { return nil }

        // Get the base format data first
        let baseData: Data?
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            baseData = try? encoder.encode(recentLogs)

        case .csv:
            var csv = "Timestamp,Level,Category,Subsystem,Message,File,Function,Line,Metadata\n"
            let formatter = ISO8601DateFormatter()

            for log in recentLogs {
                let timestamp = formatter.string(from: log.timestamp)
                let escapedMessage = log.message.replacingOccurrences(of: "\"", with: "\"\"")
                let metadataStr = log.metadata?.map { "\($0.key)=\($0.value.stringValue)" }
                    .joined(separator: "; ") ?? ""
                let escapedMetadata = metadataStr.replacingOccurrences(of: "\"", with: "\"\"")
                csv += "\"\(timestamp)\",\"\(log.level.rawValue)\",\"\(log.category)\",\"\(log.subsystem)\",\"\(escapedMessage)\",\"\(log.file)\",\"\(log.function)\",\(log.line),\"\(escapedMetadata)\"\n"
            }

            baseData = csv.data(using: .utf8)

        case .txt:
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .long

            var text = ""
            for log in recentLogs {
                var line = "\(log.level.visualQueue) [\(formatter.string(from: log.timestamp))] [\(log.level.displayName.uppercased())] [\(log.category)] [\(log.file)] \(log.message)"
                if let metadata = log.metadata, !metadata.isEmpty {
                    let metadataStr = metadata.map { "\($0.key)=\($0.value.stringValue)" }.joined(separator: ", ")
                    line += " {\(metadataStr)}"
                }
                text += line + "\n"
            }
         
            baseData = text.data(using: .utf8)
        }

        guard let data = baseData else { return nil }

        return data
    }
    
    func logStatistics() -> LogStatistics {
        guard !recentLogs.isEmpty else {
            return .empty
        }

        let calendar = Calendar.current
        var countByLevel: [LogLevel: Int] = [:]
        var countByCategory: [LogCategory: Int] = [:]
        var hourlyDistribution: [Int: Int] = [:]
        var dailyDistribution: [Date: Int] = [:]
        var minDate: Date?
        var maxDate: Date?

        for log in recentLogs {
            countByLevel[log.level, default: 0] += 1
            countByCategory[log.category, default: 0] += 1

            let hour = calendar.component(.hour, from: log.timestamp)
            hourlyDistribution[hour, default: 0] += 1

            let dayStart = calendar.startOfDay(for: log.timestamp)
            dailyDistribution[dayStart, default: 0] += 1

            minDate = min(minDate ?? log.timestamp, log.timestamp)
            maxDate = max(maxDate ?? log.timestamp, log.timestamp)
        }

        let peakHour = hourlyDistribution.max { $0.value < $1.value }?.key

        let dateRange: ClosedRange<Date>? = if let minDate, let maxDate {
            minDate...maxDate
        } else {
            nil
        }

        return LogStatistics(totalCount: recentLogs.count,
                             countByLevel: countByLevel,
                             countByCategory: countByCategory,
                             hourlyDistribution: hourlyDistribution,
                             dailyDistribution: dailyDistribution,
                             peakHour: peakHour,
                             dateRange: dateRange)
    }
}

// MARK: - Convenience Logging Methods

/// Convenience methods for common logging operations with automatic level assignment.
public extension LogRService {
    /// Logs a debug-level message.
    ///
    /// Debug messages are intended for development and should contain detailed information
    /// useful for debugging. These are typically disabled in production builds.
    ///
    /// - Parameters:
    ///   - message: The message to log.
    ///   - category: The log category. Defaults to `.debug`.
    ///   - file: The source file (automatically captured).
    ///   - function: The function name (automatically captured).
    ///   - line: The line number (automatically captured).
    ///   - metadata: Optional structured key-value metadata for the log entry.
    ///
    /// ## Example
    /// ```swift
    /// logger.debug("Cache hit for key: \(key)", category: .cache)
    /// logger.debug("User profile loaded", category: .user, metadata: ["userId": .string("123")])
    /// ```
    func debug(_ message: @autoclosure () -> String,
               category: LogCategory = .debug,
               file: String = #file,
               function: String = #function,
               line: Int = #line,
               metadata: [String: LogMetadataValue]? = nil) {
        log(level: .debug, message: message(), category: category, file: file, function: function, line: line,
            metadata: metadata)
    }

    /// Logs an informational message.
    ///
    /// Info messages represent general information about app state and operations.
    /// They're useful for tracking normal app flow and significant events.
    ///
    /// - Parameters:
    ///   - message: The message to log.
    ///   - category: The log category. Defaults to `.system`.
    ///   - file: The source file (automatically captured).
    ///   - function: The function name (automatically captured).
    ///   - line: The line number (automatically captured).
    ///   - metadata: Optional structured key-value metadata for the log entry.
    ///
    /// ## Example
    /// ```swift
    /// logger.info("User logged in successfully", category: .authentication, metadata: ["method": "oauth"])
    /// logger.info("Data sync completed", category: .sync)
    /// ```
    func info(_ message: @autoclosure () -> String,
              category: LogCategory = .system,
              file: String = #file,
              function: String = #function,
              line: Int = #line,
              metadata: [String: LogMetadataValue]? = nil) {
        log(level: .info, message: message(), category: category, file: file, function: function, line: line,
            metadata: metadata)
    }

    /// Logs a notice-level message.
    ///
    /// Notice messages indicate significant events that are expected and user-visible.
    /// These are more important than info messages but don't indicate problems.
    ///
    /// - Parameters:
    ///   - message: The message to log.
    ///   - category: The log category. Defaults to `.system`.
    ///   - file: The source file (automatically captured).
    ///   - function: The function name (automatically captured).
    ///   - line: The line number (automatically captured).
    ///   - metadata: Optional structured key-value metadata for the log entry.
    ///
    /// ## Example
    /// ```swift
    /// logger.notice("Payment processed successfully", category: .payment, metadata: ["amount": .double(99.99)])
    /// logger.notice("Configuration updated", category: .configuration)
    /// ```
    func notice(_ message: @autoclosure () -> String,
                category: LogCategory = .system,
                file: String = #file,
                function: String = #function,
                line: Int = #line,
                metadata: [String: LogMetadataValue]? = nil) {
        log(level: .notice, message: message(), category: category, file: file, function: function, line: line,
            metadata: metadata)
    }

    /// Logs a warning-level message.
    ///
    /// Warning messages indicate unexpected but non-fatal conditions that should be
    /// investigated. The app can continue to function normally.
    ///
    /// - Parameters:
    ///   - message: The message to log.
    ///   - category: The log category. Defaults to `.system`.
    ///   - file: The source file (automatically captured).
    ///   - function: The function name (automatically captured).
    ///   - line: The line number (automatically captured).
    ///   - metadata: Optional structured key-value metadata for the log entry.
    ///
    /// ## Example
    /// ```swift
    /// logger.warning("API response slow: 3.2s", category: .network, metadata: ["endpoint": "/api/users"])
    /// logger.warning("Low memory warning received", category: .memory)
    /// ```
    func warning(_ message: @autoclosure () -> String,
                 category: LogCategory = .system,
                 file: String = #file,
                 function: String = #function,
                 line: Int = #line,
                 metadata: [String: LogMetadataValue]? = nil) {
        log(level: .warning, message: message(), category: category, file: file, function: function, line: line,
            metadata: metadata)
    }

    /// Logs an error-level message.
    ///
    /// Error messages indicate significant problems that prevent specific operations
    /// from completing, but don't halt the entire app. These should be investigated.
    ///
    /// - Parameters:
    ///   - message: The message to log.
    ///   - category: The log category. Defaults to `.system`.
    ///   - file: The source file (automatically captured).
    ///   - function: The function name (automatically captured).
    ///   - line: The line number (automatically captured).
    ///   - metadata: Optional structured key-value metadata for the log entry.
    ///
    /// ## Example
    /// ```swift
    /// logger.error("Failed to load user data: \(error)", category: .database, metadata: ["errorCode": .int(500)])
    /// logger.error("Network request failed", category: .network)
    /// ```
    func error(_ message: @autoclosure () -> String,
               category: LogCategory = .system,
               file: String = #file,
               function: String = #function,
               line: Int = #line,
               metadata: [String: LogMetadataValue]? = nil) {
        log(level: .error, message: message(), category: category, file: file, function: function, line: line,
            metadata: metadata)
    }

    /// Logs a fault-level message.
    ///
    /// Fault messages represent critical system-level errors that require immediate attention.
    /// These indicate serious problems that may cause the app to behave incorrectly or crash.
    ///
    /// - Parameters:
    ///   - message: The message to log.
    ///   - category: The log category. Defaults to `.system`.
    ///   - file: The source file (automatically captured).
    ///   - function: The function name (automatically captured).
    ///   - line: The line number (automatically captured).
    ///   - metadata: Optional structured key-value metadata for the log entry.
    ///
    /// ## Example
    /// ```swift
    /// logger.fault("Database connection lost", category: .database, metadata: ["retryCount": .int(3)])
    /// logger.fault("Invariant violation detected", category: .system)
    /// ```
    func fault(_ message: @autoclosure () -> String,
               category: LogCategory = .system,
               file: String = #file,
               function: String = #function,
               line: Int = #line,
               metadata: [String: LogMetadataValue]? = nil) {
        log(level: .fault, message: message(), category: category, file: file, function: function, line: line,
            metadata: metadata)
    }
}
