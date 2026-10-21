//
//  LogMessage.swift
//  Logr
//

import CryptoKit
import Foundation

/// A log message whose interpolated values each carry a ``LogPrivacy``.
///
/// Write it as a string literal; every interpolation takes an optional `privacy:` argument:
///
/// ```swift
/// logger.info("Fetched \(count) items for \(email, privacy: .private(mask: .hash))", category: .network)
/// ```
///
/// Without one, a value gets ``LogPrivacy/auto``: integers, floating-point numbers and Booleans (and their
/// optionals) are public, everything else is private, as in OSLog. Literal text is always public. Any value can be
/// interpolated: strings and numbers render as themselves, other values with `String(describing:)`, and `nil` as
/// `nil`.
///
/// A `String` you already hold is not a `LogMessage`; wrap it and choose its privacy:
/// `LogMessage(text, privacy: .public)`. Interpolating it, `"\(text)"`, makes it private.
public struct LogMessage: Sendable, ExpressibleByStringInterpolation, CustomStringConvertible {
    /// A value that is not public.
    struct Redaction: Sendable, Equatable {
        enum Kind: Sendable, Equatable {
            case `private`, hashed, sensitive
        }

        /// UTF-8 offsets into ``LogMessage/text``.
        let range: Range<Int>
        let kind: Kind
    }

    /// The message with every value in clear.
    let text: String
    /// The values that are not public, in order.
    let redactions: [Redaction]

    public init(stringLiteral value: String) {
        text = value
        redactions = []
    }

    public init(stringInterpolation: StringInterpolation) {
        text = stringInterpolation.text
        redactions = stringInterpolation.redactions
    }

    /// A message made of an existing string, with the privacy you choose for it.
    public init(_ string: String, privacy: LogPrivacy) {
        var interpolation = StringInterpolation(literalCapacity: 0, interpolationCount: 1)
        interpolation.append(string, privacy: privacy, isPublicByDefault: false)
        self.init(stringInterpolation: interpolation)
    }

    /// The message with `<private>` or `<sensitive>` in place of every value that is not public.
    public var description: String {
        rendered(keepingPrivateValues: false, hashKey: nil).text
    }
}

// MARK: - Interpolation

public extension LogMessage {
    /// Builds a ``LogMessage`` from a string literal. Each `appendInterpolation` takes a `privacy:` argument that
    /// defaults to ``LogPrivacy/auto``.
    struct StringInterpolation: StringInterpolationProtocol {
        var text = ""
        var redactions: [Redaction] = []

        public init(literalCapacity: Int, interpolationCount: Int) {
            text.reserveCapacity(literalCapacity + interpolationCount * 8)
        }

        public mutating func appendLiteral(_ literal: String) {
            text += literal
        }

        /// Appends a string, private by default.
        public mutating func appendInterpolation(_ value: String, privacy: LogPrivacy = .auto) {
            append(value, privacy: privacy, isPublicByDefault: false)
        }

        /// Appends an optional string, or `nil`; private by default.
        public mutating func appendInterpolation(_ value: String?, privacy: LogPrivacy = .auto) {
            append(value ?? "nil", privacy: privacy, isPublicByDefault: false)
        }

        /// Appends an integer, public by default.
        public mutating func appendInterpolation(_ value: some BinaryInteger, privacy: LogPrivacy = .auto) {
            append(value.description, privacy: privacy, isPublicByDefault: true)
        }

        /// Appends an optional integer, or `nil`; public by default.
        public mutating func appendInterpolation(_ value: (some BinaryInteger)?, privacy: LogPrivacy = .auto) {
            append(value?.description ?? "nil", privacy: privacy, isPublicByDefault: true)
        }

        /// Appends a floating-point number, public by default.
        public mutating func appendInterpolation(_ value: some BinaryFloatingPoint, privacy: LogPrivacy = .auto) {
            append(String(describing: value), privacy: privacy, isPublicByDefault: true)
        }

        /// Appends an optional floating-point number, or `nil`; public by default.
        public mutating func appendInterpolation(_ value: (some BinaryFloatingPoint)?,
                                                 privacy: LogPrivacy = .auto) {
            append(value.map { String(describing: $0) } ?? "nil", privacy: privacy, isPublicByDefault: true)
        }

        /// Appends a Boolean, public by default.
        public mutating func appendInterpolation(_ value: Bool, privacy: LogPrivacy = .auto) {
            append(value.description, privacy: privacy, isPublicByDefault: true)
        }

        /// Appends an optional Boolean, or `nil`; public by default.
        public mutating func appendInterpolation(_ value: Bool?, privacy: LogPrivacy = .auto) {
            append(value?.description ?? "nil", privacy: privacy, isPublicByDefault: true)
        }

        /// Appends any other value with `String(describing:)`, private by default.
        public mutating func appendInterpolation(_ value: some Any, privacy: LogPrivacy = .auto) {
            append(String(describing: value), privacy: privacy, isPublicByDefault: false)
        }

        /// Appends any other optional value with `String(describing:)`, or `nil`; private by default.
        public mutating func appendInterpolation(_ value: (some Any)?, privacy: LogPrivacy = .auto) {
            append(value.map { String(describing: $0) } ?? "nil", privacy: privacy, isPublicByDefault: false)
        }

        mutating func append(_ value: String, privacy: LogPrivacy, isPublicByDefault: Bool) {
            let start = text.utf8.count
            text += value
            guard let kind = privacy.redaction(isPublicByDefault: isPublicByDefault) else { return }
            redactions.append(Redaction(range: start..<text.utf8.count, kind: kind))
        }
    }
}

// MARK: - Rendering

extension LogMessage {
    /// The message with each value that is not public either kept in clear, its UTF-8 range in the result
    /// listed in `privateRanges`, or replaced by its placeholder. ``LogPrivacy/sensitive`` values are always
    /// replaced; hashed values without `hashKey` render as `<private>`.
    package func rendered(keepingPrivateValues: Bool,
                          hashKey: SymmetricKey?) -> (text: String, privateRanges: [Range<Int>]) {
        guard !redactions.isEmpty else { return (text, []) }
        if keepingPrivateValues, !redactions.contains(where: { $0.kind == .sensitive }) {
            return (text, redactions.map(\.range))
        }
        var privateRanges: [Range<Int>] = []
        var text = text
        let rendered = text.withUTF8 { source in
            let capacity = source.count + redactions.count * Self.hashedPlaceholderLength
            return String(unsafeUninitializedCapacity: capacity) { output in
                var written = 0
                var cursor = 0
                for redaction in redactions {
                    written = output[written...]
                        .initialize(fromContentsOf: source[cursor..<redaction.range.lowerBound])
                    let value = UnsafeBufferPointer(rebasing: source[redaction.range])
                    if keepingPrivateValues, redaction.kind != .sensitive {
                        privateRanges.append(written..<(written + value.count))
                        written = output[written...].initialize(fromContentsOf: value)
                    } else {
                        let placeholder = Self.placeholder(for: redaction.kind, value: value, hashKey: hashKey)
                        written = output[written...].initialize(fromContentsOf: placeholder)
                    }
                    cursor = redaction.range.upperBound
                }
                return output[written...].initialize(fromContentsOf: source[cursor...])
            }
        }
        return (rendered, privateRanges)
    }

    /// The message split around its ``LogPrivacy/private`` values, for the OSLog mirror: public text and private
    /// values alternate, starting and ending with public text (empty when a value is at either end). The public
    /// text is cut from `redacted`, this message rendered without private values with the same `hashKey`, so
    /// hashed and sensitive values keep their placeholders without being hashed again.
    package func mirrorParts(redacted: String, hashKey: SymmetricKey?) -> [String] {
        var parts: [String] = []
        parts.reserveCapacity(redactions.count * 2 + 1)
        var text = text
        var redacted = redacted
        text.withUTF8 { source in
            redacted.withUTF8 { output in
                var pieceStart = 0
                var position = 0
                var cursor = 0
                for redaction in redactions {
                    position += redaction.range.lowerBound - cursor
                    let placeholderLength = switch redaction.kind {
                    case .private: Self.privatePlaceholder.count
                    case .sensitive: Self.sensitivePlaceholder.count
                    case .hashed: hashKey == nil ? Self.privatePlaceholder.count : Self.hashedPlaceholderLength
                    }
                    if redaction.kind == .private {
                        parts.append(String(decoding: output[pieceStart..<position], as: UTF8.self))
                        parts.append(String(decoding: source[redaction.range], as: UTF8.self))
                        pieceStart = position + placeholderLength
                    }
                    position += placeholderLength
                    cursor = redaction.range.upperBound
                }
                assert(position + source.count - cursor == output.count, "redacted was rendered differently")
                parts.append(String(decoding: output[pieceStart...], as: UTF8.self))
            }
        }
        return parts
    }

    private static let privatePlaceholder = Array(LogPrivacy.privatePlaceholder.utf8)
    private static let sensitivePlaceholder = Array(LogPrivacy.sensitivePlaceholder.utf8)
    /// `<private:` and `>` around 8 hex digits; the longest placeholder.
    private static let hashedPlaceholderLength = 18
    private static let hexDigits = Array("0123456789abcdef".utf8)

    private static func placeholder(for kind: Redaction.Kind, value: UnsafeBufferPointer<UInt8>,
                                    hashKey: SymmetricKey?) -> [UInt8] {
        switch kind {
        case .private:
            return privatePlaceholder
        case .sensitive:
            return sensitivePlaceholder
        case .hashed:
            guard let hashKey else { return privatePlaceholder }
            var placeholder = Array("<private:".utf8)
            for byte in HMAC<SHA256>.authenticationCode(for: UnsafeRawBufferPointer(value), using: hashKey)
                .prefix(4) {
                placeholder += [hexDigits[Int(byte >> 4)], hexDigits[Int(byte & 0x0F)]]
            }
            placeholder.append(UInt8(ascii: ">"))
            return placeholder
        }
    }
}
