//  
//  LogLevel.swift
//  Logr
//
//  Created by martin on 14/09/2025.
//

import Foundation
import OSLog

public enum LogLevel: String, CaseIterable, Sendable, Codable {
    // debug: Debug-level messages to use in a development environment while actively debugging.
    case debug
    // info: Call this function to capture information that may be helpful, but isn’t essential, for troubleshooting. High-level system events (start, stop, config).
    case info
    // notice: User-visible, expected events.
    case notice
    // warning: Warning-level messages for reporting unexpected non-fatal failures / Non-critical recoverable issues..
    case warning
    // error: Error-level messages for reporting critical errors and failures / Significant runtime errors.
    case error
    // fault: messages for capturing system-level or multi-process errors only / Invariant violations, programming bugs.
    case fault
    
    public var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .notice: return .info
        case .warning: return .default
        case .error: return .error
        case .fault: return .fault
        }
    }
    
    public var displayName: String {
        switch self {
        case .debug: return "Debug"
        case .info: return "Info"
        case .notice: return "Notice"
        case .warning: return "Notice"
        case .error: return "Error"
        case .fault: return "Fault"
        }
    }
    
    public var priority: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .notice : return 2
        case .warning: return 3
        case .error: return 4
        case .fault: return 5
        }
    }
    
    var visualQueue: String {
        switch self {
        case .debug: "🟣"
        case .info, .notice: "🔵"
        case .warning: "🟡"
        case .fault, .error: "🔴"
        }
    }
}
