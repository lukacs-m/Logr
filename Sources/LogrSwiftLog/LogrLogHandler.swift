//
//  LogrLogHandler.swift
//  LogrSwiftLog
//

import Logging
import Logr

/// A swift-log `LogHandler` that records every event in a `LogRService`.
///
/// Bootstrap swift-log once, at launch, with the service the app logs to:
///
/// ```swift
/// let logger = LogR(storage: .sqlite())
/// LoggingSystem.bootstrap { label in LogrLogHandler(label: label, logger: logger) }
/// ```
///
/// Each event becomes a `LogEntry` like one logged through `LogRService`: same level filter, storage,
/// encryption and OSLog mirror, and it carries `LogContext.metadata` under its own.
///
/// | swift-log | Logr |
/// |---|---|
/// | `trace`, `debug` | `LogLevel.debug` |
/// | `info` | `LogLevel.info` |
/// | `notice` | `LogLevel.notice` |
/// | `warning` | `LogLevel.warning` |
/// | `error` | `LogLevel.error` |
/// | `critical` | `LogLevel.fault` |
///
/// The event's error is appended to the message as a private value, as `"\(error)"` would be in a
/// `LogMessage`. Metadata merges the handler's ``metadata``, then the ``metadataProvider``'s, then the event's,
/// each winning over the previous one; then the event's `source` replaces any `source` key when it is not the
/// module of the event's file. Values tagged with ``LogrSensitivity`` other than `public` are
/// stored as `<private>` or `<sensitive>` in every build: Logr metadata has no per-value privacy, so a value kept
/// in clear would show in exports too.
public struct LogrLogHandler: LogHandler {
    /// Metadata added to every event logged through this handler.
    public var metadata: Logger.Metadata = [:]

    /// The lowest level forwarded to the service, which then applies its own `LogrConfiguration`. Defaults to
    /// `info`, as swift-log's handlers do, so dependencies' `trace` and `debug` events are not built or recorded;
    /// lower it on a `Logger` to record them.
    public var logLevel: Logger.Level = .info

    /// Called on every event for metadata merged over ``metadata``.
    public var metadataProvider: Logger.MetadataProvider?

    private let logger: any LogRService
    private let category: LogCategory
    private let messagePrivacy: LogPrivacy

    /// Creates a handler for the swift-log logger named `label`.
    ///
    /// - Parameters:
    ///   - label: The swift-log logger's label.
    ///   - logger: The service that records the events.
    ///   - category: The category of every event; defaults to `LogCategory(rawValue: label)`, or `"swift-log"`
    ///     for an empty label such as that of swift-log's unbound `Logger.current`.
    ///   - messagePrivacy: The privacy of the whole message, which swift-log does not split into values.
    ///     Defaults to `LogPrivacy.public`: with `LogPrivacy.auto` or `LogPrivacy.private`,
    ///     release builds would store every bridged message as `<private>`.
    ///   - metadataProvider: Called on every event; defaults to the one passed to `LoggingSystem.bootstrap`.
    public init(label: String,
                logger: any LogRService,
                category: LogCategory? = nil,
                messagePrivacy: LogPrivacy = .public,
                metadataProvider: Logger.MetadataProvider? = LoggingSystem.metadataProvider) {
        self.logger = logger
        self.category = category ?? LogCategory(rawValue: label.isEmpty ? "swift-log" : label)
        self.messagePrivacy = messagePrivacy
        self.metadataProvider = metadataProvider
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(event: LogEvent) {
        logger.record(level: LogLevel(event.level),
                      message: entryMessage(for: event),
                      category: category,
                      file: event.file,
                      function: event.function,
                      line: Int(clamping: event.line),
                      metadata: LogContext.metadata(mergedWith: entryMetadata(for: event)))
    }

    private func entryMessage(for event: LogEvent) -> LogMessage {
        let text = event.message.description
        guard let error = event.error else { return LogMessage(text, privacy: messagePrivacy) }
        return "\(text, privacy: messagePrivacy) \(error)"
    }

    private func entryMetadata(for event: LogEvent) -> [String: LogMetadataValue]? {
        var result = metadata.mapValues(LogMetadataValue.init)
        for (key, value) in metadataProvider?.get() ?? [:] {
            result[key] = LogMetadataValue(value)
        }
        for (key, value) in event.metadata ?? [:] {
            result[key] = LogMetadataValue(value)
        }
        let source = event.source
        // "n/a" is swift-log's source for a file with no module prefix.
        if source != "n/a", source != event.file.prefix(while: { $0 != "/" }) {
            result["source"] = .string(source)
        }
        return result.isEmpty ? nil : result
    }
}

/// How ``LogrLogHandler`` stores a swift-log metadata value.
///
/// Tag a value with it through swift-log's metadata value attributes:
///
/// ```swift
/// swiftLogger.info("Signed in", metadata: ["email": .attributed(email, attributes: [LogrSensitivity.private])])
/// ```
///
/// Untagged values are stored as given, like any Logr metadata. So are values tagged only with another attribute
/// type, such as a dependency's own sensitivity attribute: swift-log does not let a handler read attributes whose
/// type it does not know.
public enum LogrSensitivity: Int64, Logger.MetadataValueAttributes.Attribute {
    /// Stored as given.
    case `public`
    /// Stored as `<private>`.
    case `private`
    /// Stored as `<sensitive>`.
    case sensitive
}

extension LogLevel {
    init(_ level: Logger.Level) {
        switch level {
        case .debug, .trace: self = .debug
        case .info: self = .info
        case .notice: self = .notice
        case .warning: self = .warning
        case .error: self = .error
        case .critical: self = .fault
        }
    }
}

extension LogMetadataValue {
    init(_ value: Logger.MetadataValue) {
        switch value {
        case let .string(string):
            self = .string(string)
        case let .stringConvertible(convertible):
            switch value.attributes[LogrSensitivity.self] {
            case .private: self = .string(LogPrivacy.privatePlaceholder)
            case .sensitive: self = .string(LogPrivacy.sensitivePlaceholder)
            case nil, .public: self = .string(convertible.description)
            }
        case let .array(values):
            self = .array(values.map(LogMetadataValue.init))
        case let .dictionary(dictionary):
            self = .dictionary(dictionary.mapValues(LogMetadataValue.init))
        }
    }
}
