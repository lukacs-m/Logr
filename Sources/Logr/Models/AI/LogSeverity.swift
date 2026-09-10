//
//  LogSeverity.swift
//  Logr
//
//  Created by Martin Lukacs on 07/12/2025.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
#if canImport(FoundationModels)
@Generable(description: "Severity level of an issue: critical, high, medium, or low")
#endif
public enum LogSeverity: Sendable, Hashable, Equatable {
    case critical
    case high
    case medium
    case low

    public var description: String {
        switch self {
        case .critical: "Critical"
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }

    public var priority: Int {
        switch self {
        case .critical: 4
        case .high: 3
        case .medium: 2
        case .low: 1
        }
    }
}
