//
//  LogAIAnalyzer.swift
//  Logr
//
//  Created by Martin Lukacs on 16/11/2025.
//

import Foundation

/// Explains the issue groups of a ``LogIssueDigest``: titles, causes, fixes, an executive summary and priority
/// actions.
///
/// ``LogRService/summarizeIssues()`` builds the digest without a model and hands it to the analyzer. The built-in
/// ``AIAnalyzer`` uses the on-device Apple Intelligence model (iOS, macOS and visionOS 26+). Privacy scanning
/// does not involve the analyzer: ``LogRService/scanForPrivacyIssues(detectors:)`` is deterministic.
///
/// A custom analyzer can use another model, on any platform:
///
/// ```swift
/// struct CustomAnalyzer: LogAIAnalyzer {   // Sendable: a struct or an actor
///     var isAvailable: Bool { true }
///
///     func summarizeIssues(_ digest: LogIssueDigest,
///                          onProgress: @escaping @MainActor @Sendable (AnalysisProgress) -> Void)
///         async throws -> LogIssueSummary {
///         let issues = digest.groups.map { group in
///             LogIssue(group: group, title: group.template, explanation: "", suggestedFix: "", severity: .medium)
///         }
///         let total = digest.groups.count
///         await onProgress(AnalysisProgress(totalGroups: total, analyzedGroups: total))
///         return LogIssueSummary(executiveSummary: "\(issues.count) issues", issues: issues,
///                                totalErrors: digest.totalErrors, totalWarnings: digest.totalWarnings,
///                                totalFaults: digest.totalFaults, patterns: [], priorityActions: [])
///     }
/// }
///
/// let logger = LogR(storage: .sqlite(), logAnalyser: CustomAnalyzer())
/// ```
public protocol LogAIAnalyzer: Sendable {
    /// Whether ``summarizeIssues(_:onProgress:)`` can run now; ``LogRService/canAnalyseLogs`` reads it.
    nonisolated var isAvailable: Bool { get }

    /// Explains each group of `digest`.
    ///
    /// Take ``LogIssueGroup/file``, ``LogIssueGroup/line``, ``LogIssueGroup/count`` and the totals from the
    /// digest: a model's own counts are not reliable.
    ///
    /// - Parameters:
    ///   - digest: A non-empty digest.
    ///   - onProgress: Called as groups are explained.
    /// - Returns: One ``LogIssue`` per digest group, in the digest's order.
    /// - Throws: ``AIAnalyzerError`` when the model is unavailable or fails before explaining any group (the
    ///   built-in ``AIAnalyzer`` returns what it explained when it fails later), `CancellationError` when
    /// cancelled.
    func summarizeIssues(_ digest: LogIssueDigest,
                         onProgress: @escaping @MainActor @Sendable (AnalysisProgress) -> Void) async throws
        -> LogIssueSummary
}
