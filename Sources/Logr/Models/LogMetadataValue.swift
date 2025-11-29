//
//  LogMetadataValue.swift
//  Logr
//
//  Created by Claude on 28/11/2025.
//

import Foundation

/// A type-safe value for structured logging metadata.
///
/// `LogMetadataValue` provides type-safe storage for common data types
/// used in structured logging. Each case wraps a specific type while
/// maintaining `Sendable`, `Codable`, and `Hashable` conformance.
///
/// ## Overview
///
/// Use `LogMetadataValue` to attach structured data to log entries:
///
/// ```swift
/// logger.info("API Request completed",
///             category: .network,
///             metadata: [
///                 "url": .string("/api/users"),
///                 "status": .int(200),
///                 "duration": .double(0.523),
///                 "cached": .bool(false)
///             ])
/// ```
///
/// ## Supported Types
///
/// - ``string(_:)`` - String values
/// - ``int(_:)`` - Integer values
/// - ``double(_:)`` - Floating-point values
/// - ``bool(_:)`` - Boolean values
/// - ``date(_:)`` - Date values
/// - ``array(_:)`` - Arrays of metadata values
/// - ``dictionary(_:)`` - Nested dictionaries
///
/// ## Topics
///
/// ### Creating Values
/// - ``string(_:)``
/// - ``int(_:)``
/// - ``double(_:)``
/// - ``bool(_:)``
/// - ``date(_:)``
/// - ``array(_:)``
/// - ``dictionary(_:)``
///
/// ### Accessing Values
/// - ``stringValue``
public enum LogMetadataValue: Sendable, Codable, Hashable, Equatable {
    /// A string value.
    case string(String)

    /// An integer value.
    case int(Int)

    /// A floating-point value.
    case double(Double)

    /// A boolean value.
    case bool(Bool)

    /// A date value.
    case date(Date)

    /// An array of metadata values.
    case array([LogMetadataValue])

    /// A nested dictionary of metadata values.
    case dictionary([String: LogMetadataValue])

    /// Returns the value as a string for display purposes.
    ///
    /// Converts any value type to its string representation.
    ///
    /// ```swift
    /// let value: LogMetadataValue = .int(200)
    /// print(value.stringValue) // "200"
    /// ```
    public var stringValue: String {
        switch self {
        case let .string(value):
            return value
        case let .int(value):
            return String(value)
        case let .double(value):
            return String(value)
        case let .bool(value):
            return String(value)
        case let .date(value):
            return value.ISO8601Format()
        case let .array(values):
            return "[\(values.map(\.stringValue).joined(separator: ", "))]"
        case let .dictionary(dict):
            let pairs = dict.map { "\($0.key): \($0.value.stringValue)" }
            return "{\(pairs.joined(separator: ", "))}"
        }
    }
}

// MARK: - ExpressibleBy Literals

extension LogMetadataValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension LogMetadataValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}

extension LogMetadataValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension LogMetadataValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension LogMetadataValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: LogMetadataValue...) {
        self = .array(elements)
    }
}

extension LogMetadataValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, LogMetadataValue)...) {
        self = .dictionary(Dictionary(uniqueKeysWithValues: elements))
    }
}
