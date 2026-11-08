//
//  LogSeverity.swift
//  Logr
//
//  Created by Martin Lukacs on 07/12/2025.
//

import Foundation

/// How serious a privacy warning or a summarized issue is.
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
