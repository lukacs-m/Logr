//
//  AIAnalyzer.swift
//  Logr
//
//  Created by martin on 02/11/2025.
//

// import Foundation
// import FoundationModels
//
///// Apple Intelligence-powered log analyzer for privacy and issue detection
// @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
// public actor AIAnalyzer: LogAIAnalyzer {
//    private let maxLogsPerRequest: Int
//    private let session: LanguageModelSession
//    private let model = SystemLanguageModel.default
//
//    public init(maxLogsPerRequest: Int = 200) {
//        self.maxLogsPerRequest = maxLogsPerRequest
//        self.session = LanguageModelSession()
//    }
//
//    public var isAvailable: Bool {
//        get  {
//            // Foundation Models is available on iOS 26+, macOS 26+
//            // Availability is checked at compile time through @available attribute
//             model.isAvailable
//        }
//    }
//
//    // MARK: - Privacy Scanning
//
//    public func scanForPrivacyIssues(logs: [LogEntry]) async throws -> PrivacyAnalysisResult {
//        guard !logs.isEmpty else {
//            throw AIAnalyzerError.noLogsToAnalyze
//        }
//
//        guard isAvailable else {
//            throw AIAnalyzerError.modelUnavailable
//        }
//
//        // Note: prewarm() may not be available in all SDK versions
//        // Uncomment if available: try? await session.prewarm()
//
//        // Handle context length by chunking if needed
//        let chunks = logs.chunked(into: maxLogsPerRequest)
//        var allWarnings: [PrivacyWarning] = []
//
//        for chunk in chunks {
//            let result = try await analyzePrivacyChunk(chunk)
//            allWarnings.append(contentsOf: result.warnings)
//        }
//
//        // Aggregate results
//        let criticalCount = allWarnings.filter { $0.severity == "critical" }.count
//        let highCount = allWarnings.filter { $0.severity == "high" }.count
//
//        let overallSummary = if allWarnings.isEmpty {
//            "No privacy concerns detected in the analyzed logs."
//        } else {
//            "Found \(allWarnings.count) potential privacy exposures: \(criticalCount) critical, \(highCount) high
//            severity."
//        }
//
//        return PrivacyAnalysisResult(
//            warnings: allWarnings,
//            summary: overallSummary,
//            criticalCount: criticalCount,
//            highCount: highCount
//        )
//    }
//
//    private func analyzePrivacyChunk(_ logs: [LogEntry]) async throws -> PrivacyAnalysisResult {
//        let logsText = formatLogsForAnalysis(logs)
//
//        let prompt = """
//        You are a security expert analyzing application logs for privacy concerns.
//
//        Carefully scan the following logs for any exposed sensitive information:
//        - Email addresses, phone numbers, physical addresses
//        - Credit card numbers, SSN, passport numbers
//        - API keys, tokens, passwords, authentication credentials
//        - Personal names (when used with other PII)
//        - Location data (GPS coordinates, specific addresses)
//        - Health information, financial data
//        - Any other personally identifiable information (PII)
//
//        For each privacy concern found:
//        1. Identify the exact file and line number
//        2. Specify the type of sensitive data exposed
//        3. Extract the actual exposed content
//        4. Explain why it's a concern
//        5. Rate severity (critical, high, medium, low)
//        6. Provide a recommendation to fix it
//
//        LOGS TO ANALYZE (\(logs.count) entries):
//        \(logsText)
//
//        Analyze thoroughly and return structured results. If no privacy issues are detected, return empty
//        warnings array with appropriate summary and zero counts.
//        """
//
//        do {
//            let response = try await session.respond(to: prompt, generating: PrivacyAnalysisResult.self)
//            return response.content
//
//        } catch {
//            throw AIAnalyzerError.systemError(error)
//        }
//    }
//
//    // MARK: - Issue Summarization
//
//    public func summarizeIssues(logs: [LogEntry]) async throws -> LogIssueSummary {
//        guard !logs.isEmpty else {
//            throw AIAnalyzerError.noLogsToAnalyze
//        }
//
//        guard isAvailable else {
//            throw AIAnalyzerError.modelUnavailable
//        }
//
//        // Note: prewarm() may not be available in all SDK versions
//        // Uncomment if available: try? await session.prewarm()
//
//        // Handle context length by chunking if needed
//        let chunks = logs.chunked(into: maxLogsPerRequest)
//        var allIssues: [LogIssue] = []
//        var errorCount = 0
//        var warningCount = 0
//        var faultCount = 0
//
//        for chunk in chunks {
//            let result = try await analyzeIssuesChunk(chunk)
//            allIssues.append(contentsOf: result.issues)
//            errorCount += result.totalErrors
//            warningCount += result.totalWarnings
//            faultCount += result.totalFaults
//        }
//
//        // Deduplicate and merge similar issues
//        let mergedIssues = mergeIssues(allIssues)
//
//        // Generate final summary if we had multiple chunks
//        if chunks.count > 1 {
//            let executiveSummary = generateExecutiveSummary(
//                issues: mergedIssues,
//                errors: errorCount,
//                warnings: warningCount,
//                faults: faultCount
//            )
//
//            let patterns = extractPatterns(from: mergedIssues)
//            let actions = prioritizeActions(from: mergedIssues)
//
//            return LogIssueSummary(
//                executiveSummary: executiveSummary,
//                issues: mergedIssues,
//                totalErrors: errorCount,
//                totalWarnings: warningCount,
//                totalFaults: faultCount,
//                patterns: patterns,
//                priorityActions: actions
//            )
//        } else if let firstChunkResult = try? await analyzeIssuesChunk(logs) {
//            return firstChunkResult
//        } else {
//            throw AIAnalyzerError.invalidResponse
//        }
//    }
//
//    private func analyzeIssuesChunk(_ logs: [LogEntry]) async throws -> LogIssueSummary {
//        let logsText = formatLogsForAnalysis(logs)
//
//        // Count errors, warnings, faults for context
//        let errors = logs.filter { $0.level == .error }.count
//        let warnings = logs.filter { $0.level == .notice }.count
//        let faults = logs.filter { $0.level == .fault }.count
//
//        let prompt = """
//        You are an expert software engineer analyzing application logs to identify issues and patterns.
//
//        Analyze the following logs and identify:
//        1. ERRORS: Actual errors that occurred (crashes, failures, exceptions)
//        2. WARNINGS: Potential problems or deprecations
//        3. PERFORMANCE: Slow operations, timeouts, memory issues
//        4. PATTERNS: Recurring issues or trends across multiple logs
//        5. ROOT CAUSES: Underlying problems causing multiple symptoms
//
//        For each issue:
//        - Provide file and line number where it occurs
//        - Count how many times it appears (occurrences)
//        - Assess severity (critical, high, medium, low)
//        - Suggest a concrete fix or next steps
//        - Group related issues together
//
//        Provide:
//        - Executive summary of overall application health
//        - List of distinct issues found
//        - Patterns identified across logs
//        - Priority actions to improve stability
//
//        LOGS TO ANALYZE (Total: \(logs.count), Errors: \(errors), Warnings: \(warnings), Faults: \(faults)):
//        \(logsText)
//
//        Focus on actionable insights that help developers improve the application.
//        """
//
//        do {
//            let response = try await session.respond(to: prompt, generating: LogIssueSummary.self)
//            return response.content
//
//        } catch {
//            throw AIAnalyzerError.systemError(error)
//        }
//    }
//
//    // MARK: - Helper Methods
//
//    private func formatLogsForAnalysis(_ logs: [LogEntry]) -> String {
//        logs.map { log in
//            let timestamp = log.timestamp.ISO8601Format()
//            let level = log.level.rawValue.uppercased()
//            let category = log.category.rawValue
//            return "[\(timestamp)] [\(level)] [\(category)] \(log.message) (\(log.file):\(log.line))"
//        }.joined(separator: "\n")
//    }
//
//    private func mergeIssues(_ issues: [LogIssue]) -> [LogIssue] {
//        var merged: [String: LogIssue] = [:]
//
//        for issue in issues {
//            let key = "\(issue.category):\(issue.title)"
//            if let existing = merged[key] {
//                // Merge occurrences
//                let newOccurrences = existing.occurrences + issue.occurrences
//                merged[key] = LogIssue(
//                    category: existing.category,
//                    title: existing.title,
//                    description: existing.description,
//                    file: existing.file,
//                    line: existing.line,
//                    occurrences: newOccurrences,
//                    severity: existing.severity,
//                    suggestedFix: existing.suggestedFix
//                )
//            } else {
//                merged[key] = issue
//            }
//        }
//
//        return Array(merged.values).sorted { $0.occurrences > $1.occurrences }
//    }
//
//    private func generateExecutiveSummary(issues: [LogIssue], errors: Int, warnings: Int, faults: Int) -> String
//    {
//        let critical = issues.filter { $0.severity == "critical" }.count
//        let high = issues.filter { $0.severity == "high" }.count
//
//        return """
//        Analyzed \(errors) errors, \(warnings) warnings, and \(faults) faults. \
//        Found \(issues.count) distinct issues: \(critical) critical, \(high) high severity. \
//        \(critical > 0 ? "Immediate action required on critical issues." : "No critical issues detected.")
//        """
//    }
//
//    private func extractPatterns(from issues: [LogIssue]) -> [String] {
//        // Group by category and identify recurring patterns
//        let grouped = Dictionary(grouping: issues) { $0.category }
//        return grouped.compactMap { category, categoryIssues in
//            if categoryIssues.count > 1 {
//                return "\(categoryIssues.count) \(category) issues detected across multiple locations"
//            }
//            return nil
//        }
//    }
//
//    private func prioritizeActions(from issues: [LogIssue]) -> [String] {
//        issues
//            .filter { $0.severity == "critical" || $0.severity == "high" }
//            .sorted { $0.severity > $1.severity }
//            .prefix(5)
//            .map { "\($0.title) (\($0.file):\($0.line))" }
//    }
// }
//
//// MARK: - Array Extension for Chunking
//
// private extension Array {
//    func chunked(into size: Int) -> [[Element]] {
//        stride(from: 0, to: count, by: size).map {
//            Array(self[$0..<Swift.min($0 + size, count)])
//        }
//    }
// }
//

import Foundation
import FoundationModels

// MARK: - Supporting Types

/// Severity levels for issues and warnings
public enum SeverityLevel: String, Sendable, CaseIterable {
    case critical, high, medium, low

    var priority: Int {
        switch self {
        case .critical: 4
        case .high: 3
        case .medium: 2
        case .low: 1
        }
    }
}

/// Configuration for the analyzer
public struct AnalyzerConfiguration: Sendable {
    public let maxLogsPerRequest: Int
    public let enableParallelProcessing: Bool
    public let prewarmModel: Bool

    public init(maxLogsPerRequest: Int = 200,
                enableParallelProcessing: Bool = false,
                prewarmModel: Bool = true) {
        self.maxLogsPerRequest = maxLogsPerRequest
        self.enableParallelProcessing = enableParallelProcessing
        self.prewarmModel = prewarmModel
    }

    public static var `default`: AnalyzerConfiguration {
        AnalyzerConfiguration()
    }
}

// MARK: - Enhanced Analyzer

/// Apple Intelligence-powered log analyzer for privacy and issue detection
@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
public actor AIAnalyzer: LogAIAnalyzer {
    // MARK: - Properties

    private let configuration: AnalyzerConfiguration
    private let model: SystemLanguageModel
    private var session: LanguageModelSession?

    enum AnalysisType {
        case privacy
        case issues
    }

    // MARK: - Initialization

    public init(configuration: AnalyzerConfiguration = .default,
                model: SystemLanguageModel = .default) {
        self.configuration = configuration
        self.model = model
    }

    // MARK: - Availability Checking

    public nonisolated var isAvailable: Bool {
        model.isAvailable
    }

    /// Gets detailed availability information
    public var availabilityDescription: String {
        switch model.availability {
        case .available:
            "Foundation Model is ready"
        case let .unavailable(reason):
            "Unavailable: \(reason.localizedReason)"
        }
    }

    // MARK: - Privacy Scanning

    public func scanForPrivacyIssues(logs: [LogEntry]) async throws -> PrivacyAnalysisResult {
        guard !logs.isEmpty else {
            throw AIAnalyzerError.noLogsToAnalyze
        }

        try ensureAvailable()
        return try await processInChunks(logs: logs, analysisType: .privacy)
    }

    // MARK: - Issue Summarization

    public func summarizeIssues(logs: [LogEntry]) async throws -> LogIssueSummary {
        guard !logs.isEmpty else {
            throw AIAnalyzerError.noLogsToAnalyze
        }

        try ensureAvailable()
        return try await processInChunks(logs: logs, analysisType: .issues)
    }

    // MARK: - Cleanup

    deinit {
        // Clean up session if needed
        session = nil
    }
}

// MARK: - Setup & Utils

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
private extension AIAnalyzer {
    func ensureAvailable() throws {
        switch model.availability {
        case .available:
            return
        case let .unavailable(reason):
            throw AIAnalyzerError.modelUnavailable(reason.localizedReason)
        }
    }

    func getSession() -> LanguageModelSession {
        if let existingSession = session {
            return existingSession
        }

        let newSession = LanguageModelSession(model: model,
                                              instructions: "You are an expert software engineer analyzing application logs to identify issues, patterns and potential privacy log concerns.")

        // Prewarm if configured
        if configuration.prewarmModel {
            newSession.prewarm()
        }

        session = newSession
        return newSession
    }
}

// MARK: - Generic Chunk Processing

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
private extension AIAnalyzer {
    func processInChunks<T: Generable & Sendable>(logs: [LogEntry],
                                                  analysisType: AnalysisType) async throws -> T {
        let chunks = logs.chunked(into: configuration.maxLogsPerRequest)

        // Fast path for single chunk
        guard chunks.count > 1 else {
            let session = getSession()
            return try await analyzeChunk(chunks[0], with: session, type: analysisType)
        }

        // Process multiple chunks
        let results: [T] = if configuration.enableParallelProcessing {
            try await processChunksParallel(chunks, type: analysisType)
        } else {
            try await processChunksSequential(chunks, type: analysisType)
        }

        // Merge results
        guard let result = mergeResults(results, type: analysisType) else {
            throw AIAnalyzerError.mergeError
        }
        return result
    }

    func processChunksParallel<T: Generable & Sendable>(_ chunks: [[LogEntry]],
                                                        type: AnalysisType) async throws -> [T] {
        try await withThrowingTaskGroup(of: T.self) { [weak self] group in
            guard let self else {
                return []
            }
            let session = await getSession()

            for chunk in chunks {
                group.addTask {
                    try await self.analyzeChunk(chunk, with: session, type: type)
                }
            }

            var results: [T] = []
            for try await result in group {
                results.append(result)
            }

            return results
        }
    }

    func processChunksSequential<T: Generable & Sendable>(_ chunks: [[LogEntry]],
                                                          type: AnalysisType) async throws -> [T] {
        let session = getSession()
        var results: [T] = []

        for chunk in chunks {
            let result: T = try await analyzeChunk(chunk, with: session, type: type)
            results.append(result)
        }

        return results
    }

    func analyzeChunk<T: Generable & Sendable>(_ logs: [LogEntry],
                                               with session: LanguageModelSession,
                                               type: AnalysisType) async throws -> T {
        let logsText = logs.formatLogsForAnalysis

        let prompt: String = if case .issues = type {
            promptForIssuesAnalysing(logs: logs, logsText: logsText)
        } else {
            promptForPrivacyCheck(logs: logs, logsText: logsText)
        }

        do {
            let response = try await session.respond(to: prompt, generating: T.self)
            return response.content
        } catch {
            throw AIAnalyzerError.systemError(error)
        }
    }
}

// MARK: - Prompt Generation

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
private extension AIAnalyzer {
    func promptForPrivacyCheck(logs: [LogEntry], logsText: String) -> String {
        """
        You are a security expert analyzing application logs for privacy concerns.

        Carefully scan the following logs for any exposed sensitive information:
        - Email addresses, phone numbers, physical addresses
        - Credit card numbers, SSN, passport numbers
        - API keys, tokens, passwords, authentication credentials
        - Personal names (when used with other PII)
        - Location data (GPS coordinates, specific addresses)
        - Health information, financial data
        - Any other personally identifiable information (PII)

        For each privacy concern found:
        1. Identify the exact file and line number
        2. Specify the type of sensitive data exposed
        3. Extract the actual exposed content
        4. Explain why it's a concern
        5. Rate severity (critical, high, medium, low)
        6. Provide a recommendation to fix it

        LOGS TO ANALYZE (\(logs.count) entries):
        \(logsText)

        Analyze thoroughly and return structured results. If no privacy issues are detected, return empty warnings array with appropriate summary and zero counts.
        """
    }

    func promptForIssuesAnalysing(logs: [LogEntry], logsText: String) -> String {
        // Count errors, warnings, faults for context
        let errors = logs.count(where: { $0.level == .error })
        let warnings = logs.count(where: { $0.level == .notice })
        let faults = logs.count(where: { $0.level == .fault })

        return """
        You are an expert software engineer analyzing application logs to identify issues and patterns.

        Analyze the following logs and identify:
        1. ERRORS: Actual errors that occurred (crashes, failures, exceptions)
        2. WARNINGS: Potential problems or deprecations
        3. PERFORMANCE: Slow operations, timeouts, memory issues
        4. PATTERNS: Recurring issues or trends across multiple logs
        5. ROOT CAUSES: Underlying problems causing multiple symptoms

        For each issue:
        - Provide file and line number where it occurs
        - Count how many times it appears (occurrences)
        - Assess severity (critical, high, medium, low)
        - Suggest a concrete fix or next steps
        - Group related issues together

        Provide:
        - Executive summary of overall application health
        - List of distinct issues found
        - Patterns identified across logs
        - Priority actions to improve stability

        LOGS TO ANALYZE (Total: \(logs.count), Errors: \(errors), Warnings: \(warnings), Faults: \(faults)):
        \(logsText)

        Focus on actionable insights that help developers improve the application.
        """
    }
}

// MARK: - Result Merging

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
private extension AIAnalyzer {
    func mergeResults<T>(_ results: [T],
                         type: AnalysisType) -> T? {
        switch type {
        case .privacy:
            guard let results = results as? [PrivacyAnalysisResult] else {
                assertionFailure("Expected results to be PrivacyAnalysisResult")
                return nil
            }
            return mergePrivacyResults(results) as? T
        case .issues:
            guard let results = results as? [LogIssueSummary] else {
                assertionFailure("Expected results to be LogIssueSummary")
                return nil
            }
            return mergeIssueResults(results) as? T
        }
    }

    func mergePrivacyResults(_ results: [PrivacyAnalysisResult]) -> PrivacyAnalysisResult {
        let allWarnings = results.flatMap(\.warnings)
        let criticalCount = allWarnings.count(where: { $0.severity == SeverityLevel.critical.rawValue })
        let highCount = allWarnings.count(where: { $0.severity == SeverityLevel.high.rawValue })

        let overallSummary = if allWarnings.isEmpty {
            "No privacy concerns detected in the analyzed logs."
        } else {
            "Found \(allWarnings.count) potential privacy exposures: \(criticalCount) critical, \(highCount) high severity."
        }

        return PrivacyAnalysisResult(warnings: allWarnings,
                                     summary: overallSummary,
                                     criticalCount: criticalCount,
                                     highCount: highCount)
    }

    func mergeIssueResults(_ results: [LogIssueSummary]) -> LogIssueSummary {
        let allIssues = results.flatMap(\.issues)
        let mergedIssues = mergeIssues(allIssues)

        let totalErrors = results.map(\.totalErrors).reduce(0, +)
        let totalWarnings = results.map(\.totalWarnings).reduce(0, +)
        let totalFaults = results.map(\.totalFaults).reduce(0, +)

        let patterns = extractPatterns(from: mergedIssues)
        let actions = prioritizeActions(from: mergedIssues)

        let executiveSummary = generateExecutiveSummary(issues: mergedIssues,
                                                        errors: totalErrors,
                                                        warnings: totalWarnings,
                                                        faults: totalFaults)

        return LogIssueSummary(executiveSummary: executiveSummary,
                               issues: mergedIssues,
                               totalErrors: totalErrors,
                               totalWarnings: totalWarnings,
                               totalFaults: totalFaults,
                               patterns: patterns,
                               priorityActions: actions)
    }
}

// MARK: - Helper Methods

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
private extension AIAnalyzer {
    func mergeIssues(_ issues: [LogIssue]) -> [LogIssue] {
        var merged: [String: LogIssue] = [:]

        for issue in issues {
            let key = "\(issue.category):\(issue.title)"
            if let existing = merged[key] {
                // Merge occurrences
                merged[key] = existing.updateOccurrences(by: issue.occurrences)
            } else {
                merged[key] = issue
            }
        }

        return Array(merged.values)
            .sorted { lhs, rhs in
                guard let lhsSeverity = SeverityLevel(rawValue: lhs.severity),
                      let rhsSeverity = SeverityLevel(rawValue: rhs.severity) else {
                    return lhs.occurrences > rhs.occurrences
                }
                return lhsSeverity.priority > rhsSeverity.priority ||
                    (lhsSeverity.priority == rhsSeverity.priority && lhs.occurrences > rhs.occurrences)
            }
    }

//    func generateExecutiveSummary(
//        issues: [LogIssue],
//        errors: Int,
//        warnings: Int,
//        faults: Int
//    ) -> String {
//        let criticalIssues = issues.compactMap { issue in
//            SeverityLevel(rawValue: issue.severity).map { ($0, issue) }
//        }.filter { $0.0 == .critical }
//
//        let highSeverityIssues = issues.compactMap { issue in
//            SeverityLevel(rawValue: issue.severity).map { ($0, issue) }
//        }.filter { $0.0 == .high }
//
//        return """
//        Analyzed \(errors) errors, \(warnings) warnings, and \(faults) faults. \
//        Found \(issues.count) distinct issues: \(criticalIssues.count) critical, \(highSeverityIssues.count) high
//        severity. \
//        \(criticalIssues.isEmpty ? "No critical issues detected." : "Immediate action required on
//        \(criticalIssues.count) critical issues.")
//        """
//    }

    func generateExecutiveSummary(issues: [LogIssue], errors: Int, warnings: Int, faults: Int) -> String {
        let critical = issues.count(where: { $0.severity == "critical" })
        let high = issues.count(where: { $0.severity == "high" })

        return """
        Analyzed \(errors) errors, \(warnings) warnings, and \(faults) faults. \
        Found \(issues.count) distinct issues: \(critical) critical, \(high) high severity. \
        \(critical > 0 ? "Immediate action required on critical issues." : "No critical issues detected.")
        """
    }

    func extractPatterns(from issues: [LogIssue]) -> [String] {
        let grouped = Dictionary(grouping: issues) { $0.category }
        return grouped.compactMap { category, categoryIssues in
            guard categoryIssues.count > 1 else { return nil }
            return "\(categoryIssues.count) \(category) issues detected across multiple locations"
        }
    }

    func prioritizeActions(from issues: [LogIssue]) -> [String] {
        issues
            .filter { $0.severity == "critical" || $0.severity == "high" }
            .sorted { $0.severity > $1.severity }
            .prefix(5)
            .map { "\($0.title) (\($0.file):\($0.line))" }
    }
}

// MARK: - Usefull extensions

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
private extension LogIssue {
    func updateOccurrences(by count: Int) -> Self {
        .init(category: category,
              title: title,
              description: description,
              file: file,
              line: line,
              occurrences: occurrences + count,
              severity: severity,
              suggestedFix: suggestedFix)
    }
}

private extension [LogEntry] {
    var formatLogsForAnalysis: String {
        map { log in
            let timestamp = log.timestamp.ISO8601Format()
            let level = log.level.rawValue.uppercased()
            let category = log.category.rawValue
            return "[\(timestamp)] [\(level)] [\(category)] \(log.message) (\(log.file):\(log.line))"
        }.joined(separator: "\n")
    }
}

// MARK: - Array Extension

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
private extension SystemLanguageModel.Availability.UnavailableReason {
    var localizedReason: String {
        switch self {
        case .deviceNotEligible:
            "Device is not eligible for Apple Intelligence analysis"
        case .appleIntelligenceNotEnabled:
            "Apple Intelligence is not enabled on this device"
        case .modelNotReady:
            "Apple Intelligence model is not ready"
        @unknown default:
            "Unknown reason"
        }
    }
}
