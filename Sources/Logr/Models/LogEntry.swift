//
//  LogEntry.swift
//  Logr
//
//  Created by martin on 02/11/2025.
//

import Foundation

/// A single log entry representing a logged message with associated metadata.
///
/// `LogEntry` is the fundamental unit of logging in LogR. Each entry contains
/// the log message, severity level, category, timestamp, and source code location.
///
/// ## Overview
///
/// Log entries are immutable value types that are:
/// - Thread-safe (`Sendable`)
/// - Persistable (`Codable`)
/// - Identifiable for SwiftUI lists
/// - Hashable for efficient comparison
///
/// ## Example
///
/// ```swift
/// let entry = LogEntry(
///     level: .info,
///     category: .network,
///     subsystem: "com.myapp",
///     message: "API request completed"
/// )
/// ```
///
/// ## Topics
///
/// ### Properties
/// - ``id``
/// - ``timestamp``
/// - ``level``
/// - ``category``
/// - ``subsystem``
/// - ``message``
/// - ``file``
/// - ``function``
/// - ``line``
/// - ``metadata``
public struct LogEntry: Sendable, Codable, Identifiable, Hashable, Equatable {
    /// Unique identifier for this log entry.
    public let id: String

    /// The timestamp when this log entry was created.
    public let timestamp: Date

    /// The severity level of this log entry.
    public let level: LogLevel

    /// The category for organizing and filtering this log.
    public let category: LogCategory

    /// The subsystem identifier (typically your app's bundle ID).
    public let subsystem: String

    /// The log message content.
    public let message: String

    /// The source file where this log was created.
    public let file: String

    /// The function name where this log was created.
    public let function: String

    /// The line number where this log was created.
    public let line: Int

    /// Optional structured metadata attached to this log entry.
    ///
    /// Use metadata to attach key-value pairs for structured logging:
    ///
    /// ```swift
    /// logger.info("Request completed",
    ///             metadata: ["url": .string("/api/users"),
    ///                        "status": .int(200),
    ///                        "duration": .double(0.5)])
    /// ```
    public let metadata: [String: LogMetadataValue]?

    /// Creates a new log entry.
    ///
    /// - Parameters:
    ///   - id: Unique identifier. Defaults to a new UUID string.
    ///   - timestamp: When the log was created. Defaults to current date.
    ///   - level: The severity level of the log.
    ///   - category: The category for organizing logs.
    ///   - subsystem: The subsystem identifier.
    ///   - message: The log message content.
    ///   - file: Source file (automatically captured).
    ///   - function: Function name (automatically captured).
    ///   - line: Line number (automatically captured).
    ///   - metadata: Optional structured metadata key-value pairs.
    public init(id: String = UUID().uuidString,
                timestamp: Date = Date(),
                level: LogLevel,
                category: LogCategory,
                subsystem: String,
                message: String,
                file: String = #file,
                function: String = #function,
                line: Int = #line,
                metadata: [String: LogMetadataValue]? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.subsystem = subsystem
        self.message = message
        self.file = file
        self.function = function
        self.line = line
        self.metadata = metadata
    }

    public static func == (lhs: LogEntry, rhs: LogEntry) -> Bool {
        lhs.id == rhs.id &&
            lhs.timestamp == rhs.timestamp &&
            lhs.level == rhs.level &&
            lhs.category == rhs.category &&
            lhs.subsystem == rhs.subsystem &&
            lhs.message == rhs.message &&
            lhs.metadata == rhs.metadata
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(timestamp)
        hasher.combine(level)
        hasher.combine(category)
        hasher.combine(subsystem)
        hasher.combine(message)
        hasher.combine(metadata)
    }
}

/// An encrypted log entry for secure persistent storage.
///
/// `EncryptedLogEntry` wraps a `LogEntry` with encryption for secure storage.
/// The actual log data is encrypted using AES-256-GCM with keys stored in the Keychain.
///
/// ## Overview
///
/// This type is used internally by the storage layer to persist logs securely.
/// The encryption and decryption are handled automatically by the crypto service.
///
/// - Note: You typically don't create these directly; they're created by the logging system.
///
/// ## Topics
///
/// ### Properties
/// - ``id``
/// - ``timestamp``
/// - ``data``
public struct EncryptedLogEntry: Sendable, Codable, Identifiable, Hashable {
    /// Unique identifier matching the original `LogEntry`.
    public let id: String

    /// The timestamp from the original `LogEntry`.
    public let timestamp: Date

    /// The encrypted log data.
    public let data: Data

    /// Creates a new encrypted log entry.
    ///
    /// - Parameters:
    ///   - id: The unique identifier from the original log entry.
    ///   - timestamp: The timestamp from the original log entry.
    ///   - data: The encrypted log data.
    public init(id: String, timestamp: Date, data: Data) {
        self.id = id
        self.timestamp = timestamp
        self.data = data
    }
}
