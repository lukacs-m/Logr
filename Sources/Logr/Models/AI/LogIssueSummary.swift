//
//  LogIssueSummary.swift
//  Logr
//
//  Created by martin on 02/11/2025.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
#if canImport(FoundationModels)
@Generable(description: "Individual issue detected in application logs")
#endif
public struct LogIssue: Sendable, Identifiable, Hashable, Equatable {
    public var id: String {
        "\(category):\(file):\(line)"
    }

    #if canImport(FoundationModels)
    @Guide(description: "Category of the issue: error, warning, crash, performance, or other")
    #endif
    public var category: String

    #if canImport(FoundationModels)
    @Guide(description: "Brief title describing the issue")
    #endif
    public var title: String

    #if canImport(FoundationModels)
    @Guide(description: "Detailed description of the issue")
    #endif
    public var description: String

    #if canImport(FoundationModels)
    @Guide(description: "The source file where the issue occurred")
    #endif
    public var file: String

    #if canImport(FoundationModels)
    @Guide(description: "The line number in the source file", .range(1...100_000))
    #endif
    public var line: Int

    #if canImport(FoundationModels)
    @Guide(description: "How many times this issue appears in the logs", .range(1...10_000))
    #endif
    public var occurrences: Int

    #if canImport(FoundationModels)
    @Guide(description: "Severity level: critical, high, medium, or low")
    #endif
    public var severity: LogSeverity

    #if canImport(FoundationModels)
    @Guide(description: "Suggested solution or next steps to resolve the issue")
    #endif
    public var suggestedFix: String

    public init(category: String,
                title: String,
                description: String,
                file: String,
                line: Int,
                occurrences: Int,
                severity: LogSeverity,
                suggestedFix: String) {
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
#if canImport(FoundationModels)
@Generable(description: "Comprehensive summary of issues found in application logs")
#endif
public struct LogIssueSummary: Sendable, Equatable {
    #if canImport(FoundationModels)
    @Guide(description: "Executive summary of the overall health of the application based on logs")
    #endif
    public var executiveSummary: String

    #if canImport(FoundationModels)
    @Guide(description: "List of all issues detected in the logs")
    #endif
    public var issues: [LogIssue]

    #if canImport(FoundationModels)
    @Guide(description: "Total number of error-level log entries analyzed", .range(0...10_000))
    #endif
    public var totalErrors: Int

    #if canImport(FoundationModels)
    @Guide(description: "Total number of warning-level log entries analyzed", .range(0...10_000))
    #endif
    public var totalWarnings: Int

    #if canImport(FoundationModels)
    @Guide(description: "Total number of fault-level log entries analyzed", .range(0...10_000))
    #endif
    public var totalFaults: Int

    #if canImport(FoundationModels)
    @Guide(description: "List of recurring patterns or trends identified across multiple logs")
    #endif
    public var patterns: [String]

    #if canImport(FoundationModels)
    @Guide(description: "Recommended priority actions to improve application stability")
    #endif
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
