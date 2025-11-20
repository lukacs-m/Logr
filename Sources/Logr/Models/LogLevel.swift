//
//  LogLevel.swift
//  Logr
//
//  Created by martin on 14/09/2025.
//

import Foundation
import OSLog

public enum LogLevel: String, CaseIterable, Sendable, Codable, Hashable, Identifiable, Equatable {
    // debug: Debug-level messages to use in a development environment while actively debugging.
    case debug
    // info: Call this function to capture information that may be helpful, but isn’t essential, for troubleshooting. High-level system events (start, stop, config).
    case info
    // notice: User-visible, expected events.
    case notice
    // warning: Warning-level messages for reporting unexpected non-fatal failures / Non-critical recoverable
    // issues..
    case warning
    // error: Error-level messages for reporting critical errors and failures / Significant runtime errors.
    case error
    // fault: messages for capturing system-level or multi-process errors only / Invariant violations, programming bugs.
    case fault

    public var osLogType: OSLogType {
        switch self {
        case .debug: .debug
        case .info: .info
        case .notice: .info
        case .warning: .default
        case .error: .error
        case .fault: .fault
        }
    }

    public var displayName: String {
        switch self {
        case .debug: "Debug"
        case .info: "Info"
        case .notice: "Notice"
        case .warning: "Notice"
        case .error: "Error"
        case .fault: "Fault"
        }
    }

    public var priority: Int {
        switch self {
        case .debug: 0
        case .info: 1
        case .notice: 2
        case .warning: 3
        case .error: 4
        case .fault: 5
        }
    }

    public var visualQueue: String {
        switch self {
        case .debug: "🟣"
        case .info, .notice: "🔵"
        case .warning: "🟡"
        case .error, .fault: "🔴"
        }
    }

    public var id: Self { self }
}
