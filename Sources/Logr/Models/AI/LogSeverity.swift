//  
//  LogSeverity.swift
//  Logr
//
//  Created by Martin Lukacs on 07/12/2025.
//

import Foundation
import FoundationModels

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
@Generable(description: "Severity level of an issue: critical, high, medium, or low")
public enum LogSeverity: Sendable , Hashable, Equatable {
    case critical
    case high
    case medium
    case low

    public var description: String {
        switch self {
        case .critical: return "Critical"
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
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
