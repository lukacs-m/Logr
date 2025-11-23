//
//  LogIssueSummary.swift
//  Logr
//
//  Created by martin on 02/11/2025.
//

import Foundation
import FoundationModels

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
@Generable(description: "Individual issue detected in application logs")
public struct LogIssue: Sendable, Identifiable, Hashable, Equatable {
    public var id: String { "\(category):\(file):\(line)" }

    @Guide(description: "Category of the issue: error, warning, crash, performance, or other")
    public var category: String

    @Guide(description: "Brief title describing the issue")
    public var title: String

    @Guide(description: "Detailed description of the issue")
    public var description: String

    @Guide(description: "The source file where the issue occurred")
    public var file: String

    @Guide(description: "The line number in the source file", .range(1...100_000))
    public var line: Int

    @Guide(description: "How many times this issue appears in the logs", .range(1...10_000))
    public var occurrences: Int

    @Guide(description: "Severity level: critical, high, medium, or low")
    public var severity: String

    @Guide(description: "Suggested solution or next steps to resolve the issue")
    public var suggestedFix: String

    public init(category: String, title: String, description: String, file: String, line: Int, occurrences: Int,
                severity: String, suggestedFix: String) {
        self.category = category
        self.title = title
        self.description = description
        self.file = file
        self.line = line
        self.occurrences = occurrences
        self.severity = severity
        self.suggestedFix = suggestedFix
    }
}

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
@Generable(description: "Comprehensive summary of issues found in application logs")
public struct LogIssueSummary: Sendable, Equatable {
    @Guide(description: "Executive summary of the overall health of the application based on logs")
    public var executiveSummary: String

    @Guide(description: "List of all issues detected in the logs")
    public var issues: [LogIssue]

    @Guide(description: "Total number of error-level log entries analyzed", .range(0...10_000))
    public var totalErrors: Int

    @Guide(description: "Total number of warning-level log entries analyzed", .range(0...10_000))
    public var totalWarnings: Int

    @Guide(description: "Total number of fault-level log entries analyzed", .range(0...10_000))
    public var totalFaults: Int

    @Guide(description: "List of recurring patterns or trends identified across multiple logs")
    public var patterns: [String]

    @Guide(description: "Recommended priority actions to improve application stability")
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
    
    public var isEmpty: Bool {
        issues.isEmpty && totalErrors == 0 && totalWarnings == 0 && totalFaults == 0
    }
    
    public static var empty: LogIssueSummary {
        LogIssueSummary(executiveSummary: "",
                        issues: [],
                        totalErrors: 0,
                        totalWarnings: 0,
                        totalFaults: 0,
                        patterns: [],
                        priorityActions: [])
    }
}
