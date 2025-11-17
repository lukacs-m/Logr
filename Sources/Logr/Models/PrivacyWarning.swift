//
//  PrivacyWarning.swift
//  Logr
//
//  Created by martin on 02/11/2025.
//

import Foundation
import FoundationModels

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
@Generable(description: "Privacy warning detected in application logs")
public struct PrivacyWarning: Sendable, Identifiable, Hashable, Equatable {
    public var id: String { "\(file):\(line):\(exposureType)" }

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
    public var severity: String

    @Guide(description: "Recommended action to fix this privacy issue")
    public var recommendation: String

    public init(file: String, line: Int, exposureType: String, exposedContent: String, explanation: String,
                severity: String, recommendation: String) {
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
