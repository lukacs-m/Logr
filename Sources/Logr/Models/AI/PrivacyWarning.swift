//
//  PrivacyWarning.swift
//  Logr
//
//  Created by martin on 02/11/2025.
//

import Foundation

// `@Generable` copies member declarations into its expansion, so `#if` must wrap whole declarations, never
// individual `@Guide` attributes.
#if LOGR_SYSTEM_MODEL
import FoundationModels

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)
@Generable(description: "Privacy warning detected in application logs")
public struct PrivacyWarning: Sendable, Identifiable, Hashable, Equatable {
    @Guide(description: "The source file where the exposure was detected")
    public var file: String

    @Guide(description: "The line number in the source file", .range(1...100_000))
    public var line: Int

    @Guide(description: "Type of private data exposed (e.g., email, phone, credit card, API key, token, SSN, address, name, location)")
    public var exposureType: String

    @Guide(description: "The actual sensitive content that was exposed")
    public var exposedContent: String

    @Guide(description: "Detailed explanation of why this is a privacy concern")
    public var explanation: String

    @Guide(description: "Severity level: critical, high, medium, or low")
    public var severity: LogSeverity

    @Guide(description: "Recommended action to fix this privacy issue")
    public var recommendation: String

    public init(file: String,
                line: Int,
                exposureType: String,
                exposedContent: String,
                explanation: String,
                severity: LogSeverity,
                recommendation: String) {
        self.file = file
        self.line = line
        self.exposureType = exposureType
        self.exposedContent = exposedContent
        self.explanation = explanation
        self.severity = severity
        self.recommendation = recommendation
    }
}

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)
@Generable(description: "Collection of privacy warnings detected in logs")
public struct PrivacyAnalysisResult: Sendable, Equatable {
    @Guide(description: "List of all privacy warnings found in the logs")
    public var warnings: [PrivacyWarning]

    @Guide(description: "Overall summary of privacy concerns found")
    public var summary: String

    @Guide(description: "Total count of critical severity warnings", .range(0...1_000))
    public var criticalCount: Int

    @Guide(description: "Total count of high severity warnings", .range(0...1_000))
    public var highCount: Int

    public init(warnings: [PrivacyWarning], summary: String, criticalCount: Int, highCount: Int) {
        self.warnings = warnings
        self.summary = summary
        self.criticalCount = criticalCount
        self.highCount = highCount
    }
}
#else
@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)
public struct PrivacyWarning: Sendable, Identifiable, Hashable, Equatable {
    public var file: String
    public var line: Int
    public var exposureType: String
    public var exposedContent: String
    public var explanation: String
    public var severity: LogSeverity
    public var recommendation: String

    public init(file: String,
                line: Int,
                exposureType: String,
                exposedContent: String,
                explanation: String,
                severity: LogSeverity,
                recommendation: String) {
        self.file = file
        self.line = line
        self.exposureType = exposureType
        self.exposedContent = exposedContent
        self.explanation = explanation
        self.severity = severity
        self.recommendation = recommendation
    }
}

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)
public struct PrivacyAnalysisResult: Sendable, Equatable {
    public var warnings: [PrivacyWarning]
    public var summary: String
    public var criticalCount: Int
    public var highCount: Int

    public init(warnings: [PrivacyWarning], summary: String, criticalCount: Int, highCount: Int) {
        self.warnings = warnings
        self.summary = summary
        self.criticalCount = criticalCount
        self.highCount = highCount
    }
}
#endif

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)
public extension PrivacyWarning {
    var id: String {
        "\(file):\(line):\(exposureType)"
    }
}

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)
public extension PrivacyAnalysisResult {
    var isEmpty: Bool {
        warnings.isEmpty
    }

    static var empty: PrivacyAnalysisResult {
        PrivacyAnalysisResult(warnings: [], summary: "", criticalCount: 0, highCount: 0)
    }
}
