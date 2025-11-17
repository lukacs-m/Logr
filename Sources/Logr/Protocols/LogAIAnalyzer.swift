//
//  LogAIAnalyzer.swift
//  Logr
//
//  Created by Martin Lukacs on 16/11/2025.
//

import Foundation

/// Protocol defining AI-powered log analysis capabilities
@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
public protocol LogAIAnalyzer: Sendable {
    /// Checks if Apple Intelligence is available on the current device
    var isAvailable: Bool { get }

    /// Scans logs for potential privacy exposures (PII, credentials, etc.)
    /// - Parameter logs: Array of log entries to analyze
    /// - Returns: Privacy analysis result with warnings and summary
    /// - Throws: AIAnalyzerError if analysis fails
    func scanForPrivacyIssues(logs: [LogEntry]) async throws -> PrivacyAnalysisResult

    /// Analyzes logs to identify errors, warnings, and patterns
    /// - Parameter logs: Array of log entries to analyze
    /// - Returns: Comprehensive summary of issues found
    /// - Throws: AIAnalyzerError if analysis fails
    func summarizeIssues(logs: [LogEntry]) async throws -> LogIssueSummary
}
