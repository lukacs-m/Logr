//
//  LogAIAnalyzer.swift
//  Logr
//
//  Created by Martin Lukacs on 16/11/2025.
//

import Foundation

/// Protocol for AI-powered log analysis using Apple Intelligence.
///
/// `LogAIAnalyzer` provides intelligent analysis of log entries to detect privacy
/// issues and summarize critical problems. It leverages Apple Intelligence (iOS 26+)
/// for on-device natural language processing.
///
/// ## Overview
///
/// The AI analyzer provides two key capabilities:
///
/// 1. **Privacy Scanning**: Detects potential privacy violations, PII exposure,
///    and compliance issues in log messages.
///
/// 2. **Issue Summarization**: Analyzes error and warning logs to identify
///    patterns and provide actionable recommendations.
///
/// ## Availability
///
/// AI analysis features require:
/// - iOS 26.0+ or macOS 26.0+ or tvOS 26.0+ or watchOS 12.0+
/// - Apple Intelligence enabled on the device
/// - Network connectivity for initial model download (cached afterward)
///
/// ## Example Usage
///
/// ```swift
/// if #available(iOS 26.0, *) {
///     let analyzer = AIAnalyzer()
///     let logger = LogR(logAnalyser: analyzer)
///
///     // Check availability
///     if logger.canAnalyseLogs {
///         // Scan for privacy issues
///         let privacyResult = try await logger.scanForPrivacyIssues()
///         print("Privacy Score: \(privacyResult.privacyScore)")
///
///         // Summarize issues
///         let summary = try await logger.summarizeIssues()
///         print("Summary: \(summary.summary)")
///     }
/// }
/// ```
///
/// ## Custom Implementation
///
/// You can provide your own AI analyzer using a different service:
///
/// ```swift
/// @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
/// class CustomAIAnalyzer: LogAIAnalyzer {
///     var isAvailable: Bool { true }
///
///     func scanForPrivacyIssues(logs: [LogEntry]) async throws -> PrivacyAnalysisResult {
///         // Use your AI service
///         return result
///     }
///
///     func summarizeIssues(logs: [LogEntry]) async throws -> LogIssueSummary {
///         // Use your AI service
///         return summary
///     }
/// }
/// ```
///
/// ## Topics
///
/// ### Availability
/// - ``isAvailable``
///
/// ### Analysis Operations
/// - ``scanForPrivacyIssues(logs:)``
/// - ``summarizeIssues(logs:)``
/// - ``scanForPrivacyIssues(logs:onProgress:)``
/// - ``summarizeIssues(logs:onProgress:)``
@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
public protocol LogAIAnalyzer: Sendable {
    /// Indicates whether Apple Intelligence is available on the current device.
    ///
    /// Returns `true` if the device supports Apple Intelligence and it's enabled.
    /// When `false`, calling analysis methods will throw an error.
    ///
    /// ## Checking Availability
    ///
    /// ```swift
    /// if #available(iOS 26.0, *) {
    ///     let logger = LogR(logAnalyser: AIAnalyzer())
    ///
    ///     if logger.canAnalyseLogs {
    ///         // AI features available
    ///         let result = try await logger.scanForPrivacyIssues()
    ///     } else {
    ///         // AI features not available
    ///         print("Apple Intelligence not available")
    ///     }
    /// }
    /// ```
    nonisolated var isAvailable: Bool { get }

    /// Scans log entries for potential privacy violations and sensitive data exposure.
    ///
    /// Uses AI to analyze log messages for:
    /// - Personally Identifiable Information (PII)
    /// - Credentials and API keys
    /// - Email addresses and phone numbers
    /// - Credit card numbers
    /// - Health information
    /// - Other sensitive data patterns
    ///
    /// - Parameter logs: Array of log entries to analyze.
    /// - Returns: A ``PrivacyAnalysisResult`` with warnings, privacy score, and recommendations.
    /// - Throws: ``AIAnalyzerError`` if AI is unavailable or analysis fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// if #available(iOS 26.0, *) {
    ///     let result = try await logger.scanForPrivacyIssues()
    ///
    ///     print("Privacy Score: \(result.privacyScore)/100")
    ///     print("Warnings: \(result.warnings.count)")
    ///
    ///     for warning in result.warnings {
    ///         print("⚠️ \(warning.severity): \(warning.message)")
    ///         print("   Recommendation: \(warning.recommendation)")
    ///     }
    /// }
    /// ```
    func scanForPrivacyIssues(logs: [LogEntry]) async throws -> PrivacyAnalysisResult

    /// Analyzes logs to identify errors, warnings, and patterns, providing intelligent summaries.
    ///
    /// Uses AI to:
    /// - Identify critical errors and their root causes
    /// - Detect patterns across related failures
    /// - Categorize issues by affected system areas
    /// - Provide actionable recommendations
    ///
    /// - Parameter logs: Array of log entries to analyze.
    /// - Returns: A ``LogIssueSummary`` with key issues, recommendations, and affected categories.
    /// - Throws: ``AIAnalyzerError`` if AI is unavailable or analysis fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// if #available(iOS 26.0, *) {
    ///     let summary = try await logger.summarizeIssues()
    ///
    ///     print("Summary: \(summary.summary)")
    ///
    ///     print("\nKey Issues:")
    ///     for issue in summary.keyIssues {
    ///         print("- \(issue)")
    ///     }
    ///
    ///     print("\nRecommendations:")
    ///     for recommendation in summary.recommendations {
    ///         print("- \(recommendation)")
    ///     }
    ///
    ///     print("\nAffected Areas:")
    ///     for category in summary.affectedCategories {
    ///         print("- \(category)")
    ///     }
    /// }
    /// ```
    func summarizeIssues(logs: [LogEntry]) async throws -> LogIssueSummary

    /// Scans log entries for privacy issues with progress reporting.
    ///
    /// - Parameters:
    ///   - logs: Array of log entries to analyze.
    ///   - onProgress: A closure called with progress updates during analysis.
    /// - Returns: A ``PrivacyAnalysisResult`` with warnings, privacy score, and recommendations.
    /// - Throws: ``AIAnalyzerError`` if AI is unavailable or analysis fails.
    func scanForPrivacyIssues(logs: [LogEntry],
                              onProgress: @escaping @Sendable (AnalysisProgress) -> Void) async throws
        -> PrivacyAnalysisResult

    /// Analyzes logs to identify issues with progress reporting.
    ///
    /// - Parameters:
    ///   - logs: Array of log entries to analyze.
    ///   - onProgress: A closure called with progress updates during analysis.
    /// - Returns: A ``LogIssueSummary`` with key issues, recommendations, and affected categories.
    /// - Throws: ``AIAnalyzerError`` if AI is unavailable or analysis fails.
    func summarizeIssues(logs: [LogEntry],
                         onProgress: @escaping @Sendable (AnalysisProgress) -> Void) async throws
        -> LogIssueSummary
}
