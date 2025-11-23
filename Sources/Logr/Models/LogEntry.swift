//
//  LogEntry.swift
//  Logr
//
//  Created by martin on 02/11/2025.
//

import Foundation

public struct LogEntry: Sendable, Codable, Identifiable, Hashable, Equatable {
    public let id: String
    public let timestamp: Date
    public let level: LogLevel
    public let category: LogCategory
    public let subsystem: String
    public let message: String
    public let file: String
    public let function: String
    public let line: Int

    public init(id: String = UUID().uuidString,
                timestamp: Date = Date(),
                level: LogLevel,
                category: LogCategory,
                subsystem: String,
                message: String,
                file: String = #file,
                function: String = #function,
                line: Int = #line) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.subsystem = subsystem
        self.message = message
        self.file = file
        self.function = function
        self.line = line
    }

    public static func == (lhs: LogEntry, rhs: LogEntry) -> Bool {
        lhs.id == rhs.id &&
            lhs.timestamp == rhs.timestamp &&
            lhs.level == rhs.level &&
            lhs.category == rhs.category &&
            lhs.subsystem == rhs.subsystem &&
            lhs.message == rhs.message
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(timestamp)
        hasher.combine(level)
        hasher.combine(category)
        hasher.combine(subsystem)
        hasher.combine(message)
    }
}

public struct EncryptedLogEntry: Sendable, Codable, Identifiable, Hashable {
    public let id: String
    public let timestamp: Date
    public let data: Data

    public init(id: String, timestamp: Date, data: Data) {
        self.id = id
        self.timestamp = timestamp
        self.data = data
    }
}
