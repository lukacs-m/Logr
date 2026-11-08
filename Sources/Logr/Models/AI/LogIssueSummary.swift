//
//  LogIssueSummary.swift
//  Logr
//
//  Created by martin on 02/11/2025.
//

import Foundation

/// One ``LogIssueGroup`` with the explanation an analyzer wrote for it.
public struct LogIssue: Sendable, Identifiable, Hashable, Equatable {
    /// The digest group: call site, template, level and exact counts.
    public var group: LogIssueGroup
    public var title: String
    public var explanation: String
    public var suggestedFix: String
    public var severity: LogSeverity

    public init(group: LogIssueGroup, title: String, explanation: String, suggestedFix: String,
                severity: LogSeverity) {
        self.group = group
        self.title = title
        self.explanation = explanation
        self.suggestedFix = suggestedFix
        self.severity = severity
    }

    /// The group's ``LogIssueGroup/id``.
    public var id: String {
        group.id
    }
}

/// The outcome of ``LogRService/summarizeIssues()``: a ``LogIssueDigest`` explained by a ``LogAIAnalyzer``.
public struct LogIssueSummary: Sendable, Equatable {
    public var executiveSummary: String
    /// One issue per digest group, in the digest's order.
    public var issues: [LogIssue]
    /// The digest's ``LogIssueDigest/totalErrors``.
    public var totalErrors: Int
    /// The digest's ``LogIssueDigest/totalWarnings``.
    public var totalWarnings: Int
    /// The digest's ``LogIssueDigest/totalFaults``.
    public var totalFaults: Int
    /// Counts drawn from the digest, such as categories with several issues.
    public var patterns: [String]
    public var priorityActions: [String]

    public init(executiveSummary: String,
                issues: [LogIssue],
                totalErrors: Int,
                totalWarnings: Int,
                totalFaults: Int,
                patterns: [String],
                priorityActions: [String]) {
        self.executiveSummary = executiveSummary
        self.issues = issues
        self.totalErrors = totalErrors
        self.totalWarnings = totalWarnings
        self.totalFaults = totalFaults
        self.patterns = patterns
        self.priorityActions = priorityActions
    }
}

public extension LogIssueSummary {
    var isEmpty: Bool {
        issues.isEmpty && totalErrors == 0 && totalWarnings == 0 && totalFaults == 0
    }

    static var empty: LogIssueSummary {
        LogIssueSummary(executiveSummary: "",
                        issues: [],
                        totalErrors: 0,
                        totalWarnings: 0,
                        totalFaults: 0,
                        patterns: [],
                        priorityActions: [])
    }
}

// MARK: - Assembly

extension LogIssueSummary {
    /// What a model wrote for one group of a chunk, the group named by its position in the chunk.
    struct Insight {
        let groupIndex: Int
        let title: String
        let explanation: String
        let suggestedFix: String
        let severity: LogSeverity
    }

    /// The issues `insights` describe, by group id. Indexes outside the chunk are dropped; the first insight for a
    /// group wins.
    static func issues(from insights: [Insight], chunk: [LogIssueGroup]) -> [String: LogIssue] {
        var issues: [String: LogIssue] = [:]
        for insight in insights where chunk.indices.contains(insight.groupIndex) {
            let group = chunk[insight.groupIndex]
            guard issues[group.id] == nil else { continue }
            issues[group.id] = LogIssue(group: group, title: insight.title, explanation: insight.explanation,
                                        suggestedFix: insight.suggestedFix, severity: insight.severity)
        }
        return issues
    }

    /// One issue per digest group in the digest's order, counts and totals from the digest. A group without an
    /// issue keeps its template as title and gets a severity from its level; without an overview, the summary
    /// and actions are counts.
    static func assemble(digest: LogIssueDigest, issues: [String: LogIssue],
                         overview: (executiveSummary: String, priorityActions: [String])?) -> LogIssueSummary {
        let issues = digest.groups.map { group in
            issues[group.id] ?? LogIssue(group: group, title: group.template, explanation: "", suggestedFix: "",
                                         severity: group.level == .fault ? .critical : group
                                             .level == .error ? .high : .medium)
        }
        let actions = issues.filter { $0.severity.priority >= LogSeverity.high.priority }.prefix(5).map {
            "\($0.title) (\($0.group.file):\($0.group.line), \($0.group.count)×)"
        }
        return LogIssueSummary(executiveSummary: overview?.executiveSummary ?? countsSummary(digest),
                               issues: issues,
                               totalErrors: digest.totalErrors,
                               totalWarnings: digest.totalWarnings,
                               totalFaults: digest.totalFaults,
                               patterns: patterns(digest),
                               priorityActions: overview?.priorityActions ?? actions)
    }

    private static func countsSummary(_ digest: LogIssueDigest) -> String {
        "\(digest.totalErrors) errors, \(digest.totalWarnings) warnings and \(digest.totalFaults) faults "
            + "at \(digest.groups.count) call sites."
    }

    /// Categories with more than one issue, most logged first.
    private static func patterns(_ digest: LogIssueDigest) -> [String] {
        Dictionary(grouping: digest.groups, by: \.category)
            .filter { $0.value.count > 1 }
            .map { category, groups in (category, groups.count, groups.reduce(0) { $0 + $1.count }) }
            .sorted { ($1.2, $0.0.rawValue) < ($0.2, $1.0.rawValue) }
            .map { category, issues, entries in "\(category.rawValue): \(issues) issues, \(entries) entries" }
    }
}
