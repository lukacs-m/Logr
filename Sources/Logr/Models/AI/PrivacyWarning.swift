//
//  PrivacyWarning.swift
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
@Generable(description: "Privacy warning detected in application logs")
#endif
public struct PrivacyWarning: Sendable, Identifiable, Hashable, Equatable {
    public var id: String {
        "\(file):\(line):\(exposureType)"
    }

    #if canImport(FoundationModels)
    @Guide(description: "The source file where the exposure was detected")
    #endif
    public var file: String

    #if canImport(FoundationModels)
    @Guide(description: "The line number in the source file", .range(1...100_000))
    #endif
    public var line: Int

    #if canImport(FoundationModels)
    @Guide(description: "Type of private data exposed (e.g., email, phone, credit card, API key, token, SSN, address, name, location)")
    #endif
    public var exposureType: String

    #if canImport(FoundationModels)
    @Guide(description: "The actual sensitive content that was exposed")
    #endif
    public var exposedContent: String

    #if canImport(FoundationModels)
    @Guide(description: "Detailed explanation of why this is a privacy concern")
    #endif
    public var explanation: String

    #if canImport(FoundationModels)
    @Guide(description: "Severity level: critical, high, medium, or low")
    #endif
    public var severity: LogSeverity

    #if canImport(FoundationModels)
    @Guide(description: "Recommended action to fix this privacy issue")
    #endif
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

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
#if canImport(FoundationModels)
@Generable(description: "Collection of privacy warnings detected in logs")
#endif
public struct PrivacyAnalysisResult: Sendable, Equatable {
    #if canImport(FoundationModels)
    @Guide(description: "List of all privacy warnings found in the logs")
    #endif
    public var warnings: [PrivacyWarning]

    #if canImport(FoundationModels)
    @Guide(description: "Overall summary of privacy concerns found")
    #endif
    public var summary: String

    #if canImport(FoundationModels)
    @Guide(description: "Total count of critical severity warnings", .range(0...1_000))
    #endif
    public var criticalCount: Int

    #if canImport(FoundationModels)
    @Guide(description: "Total count of high severity warnings", .range(0...1_000))
    #endif
    public var highCount: Int

    public init(warnings: [PrivacyWarning], summary: String, criticalCount: Int, highCount: Int) {
        self.warnings = warnings
        self.summary = summary
        self.criticalCount = criticalCount
        self.highCount = highCount
    }

    public var isEmpty: Bool {
        warnings.isEmpty
    }

    public static var empty: PrivacyAnalysisResult {
        PrivacyAnalysisResult(warnings: [], summary: "", criticalCount: 0, highCount: 0)
    }
}
