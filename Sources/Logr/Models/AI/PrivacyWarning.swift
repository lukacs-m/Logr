//
//  PrivacyWarning.swift
//  Logr
//
//  Created by martin on 02/11/2025.
//

import Foundation

/// Values one ``PrivacyDetector`` found at one call site.
public struct PrivacyWarning: Sendable, Identifiable, Hashable, Equatable {
    /// The `#fileID` of the call site.
    public var file: String
    /// The line of the call site.
    public var line: Int
    /// The ``PrivacyDetector/name`` of the detector that matched.
    public var detector: String
    public var severity: LogSeverity
    /// How many values the detector matched at this call site, across every scanned entry.
    public var occurrences: Int
    /// The text around the newest match, every matched value replaced by `[detector name]`.
    public var excerpt: String
    /// Where the newest match was: `message`, or a metadata key path such as `http.request_headers.Cookie`.
    public var field: String

    public init(file: String,
                line: Int,
                detector: String,
                severity: LogSeverity,
                occurrences: Int,
                excerpt: String,
                field: String) {
        self.file = file
        self.line = line
        self.detector = detector
        self.severity = severity
        self.occurrences = occurrences
        self.excerpt = excerpt
        self.field = field
    }

    /// `file:line:detector`, unique within a ``PrivacyAnalysisResult``.
    public var id: String {
        "\(file):\(line):\(detector)"
    }
}

/// The outcome of ``LogRService/scanForPrivacyIssues(detectors:)``.
public struct PrivacyAnalysisResult: Sendable, Equatable {
    /// Sorted by severity, then occurrences (both descending), then ``PrivacyWarning/id``.
    public var warnings: [PrivacyWarning]
    /// One sentence that counts the warnings by severity.
    public var summary: String
    /// The number of ``LogSeverity/critical`` warnings.
    public var criticalCount: Int
    /// The number of ``LogSeverity/high`` warnings.
    public var highCount: Int

    public init(warnings: [PrivacyWarning], summary: String, criticalCount: Int, highCount: Int) {
        self.warnings = warnings
        self.summary = summary
        self.criticalCount = criticalCount
        self.highCount = highCount
    }
}

public extension PrivacyAnalysisResult {
    var isEmpty: Bool {
        warnings.isEmpty
    }

    static var empty: PrivacyAnalysisResult {
        PrivacyAnalysisResult(warnings: [], summary: "", criticalCount: 0, highCount: 0)
    }
}
