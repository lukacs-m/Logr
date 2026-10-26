//
//  NetworkLogger.swift
//  LogrNetwork
//

import Foundation
import Logr

/// Records HTTP requests in a Logr service, one `LogEntry` per request.
///
/// Requests are captured only where you opt in, without swizzling: call
/// `URLSession/loggedData(for:to:file:function:line:)` or
/// `URLSession/loggedUpload(for:from:to:file:function:line:)`, or give a session
/// ``LogrURLSessionProxyDelegate``. Each entry has category `.http`, a message such as
/// `GET /users → 200 (84 ms)` (the path is public, the query is never in it) and the fields of
/// ``HTTPLogFields`` as metadata, so retention, encryption, export and `LogContext` apply as to any other entry.
/// The level follows the outcome: `.info` for 1xx-3xx, `.warning` for 4xx, `.error` for 5xx and failures,
/// `.notice` for a cancelled request.
///
/// Bodies are not kept unless ``NetworkLoggerConfiguration/captureBodies`` is on, and never go into the entry:
/// they are encrypted with `cryptoService` into `Application Support/<bundle id>/Logr/http-bodies/` (excluded from
/// backups), where only the newest ``NetworkLoggerConfiguration/maxStoredBodies`` requests' bodies are kept; the
/// entry carries ``HTTPLogFields/bodyID`` and ``body(id:)`` reads them back. `clearLogs()` does not reach that
/// directory: call ``clearBodies()`` next to it.
///
/// Create one `NetworkLogger` per process: two would each prune the shared directory to their own limit.
///
/// ```swift
/// let network = NetworkLogger(logger: logger)
/// let (data, response) = try await URLSession.shared.loggedData(for: request, to: network)
/// ```
public final class NetworkLogger: Sendable {
    /// The configuration, limits raised to at least 1.
    public let configuration: NetworkLoggerConfiguration
    let service: any LogRService
    let bodyStore: NetworkBodyStore
    private let redactedHeaders: Set<String>
    private let redactedKeys: Set<String>

    /// Creates a logger that records requests in `logger`.
    ///
    /// - Parameters:
    ///   - logger: The service entries are recorded in.
    ///   - configuration: What to redact and whether to keep bodies.
    ///   - cryptoService: Encrypts kept bodies. Pass the one your `LogR` uses; the default reads the same Keychain
    ///     key as a default `LogR`, but a separate instance does not see a key rotation until relaunch.
    public convenience init(logger: any LogRService,
                            configuration: NetworkLoggerConfiguration = NetworkLoggerConfiguration(),
                            cryptoService: any LoggerCryptoServicing = LoggerCryptoService()) {
        let directory = URL.applicationSupportDirectory
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "LogRPersistence")
            .appendingPathComponent("Logr/http-bodies", isDirectory: true)
        self.init(logger: logger, configuration: configuration, cryptoService: cryptoService,
                  bodyDirectory: directory)
    }

    /// Bodies in `bodyDirectory`, so tests never touch Application Support.
    init(logger: any LogRService, configuration: NetworkLoggerConfiguration,
         cryptoService: any LoggerCryptoServicing, bodyDirectory: URL) {
        var configuration = configuration
        configuration.maxBodyBytes = max(1, configuration.maxBodyBytes)
        configuration.maxStoredBodies = max(1, configuration.maxStoredBodies)
        self.configuration = configuration
        service = logger
        bodyStore = NetworkBodyStore(directory: bodyDirectory, crypto: cryptoService,
                                     limit: configuration.maxStoredBodies)
        redactedHeaders = Set(configuration.redactedHeaders.map { $0.lowercased() })
        redactedKeys = Set(configuration.redactedKeys.map { $0.lowercased() })
    }

    /// The bodies kept for the entry whose ``HTTPLogFields/bodyID`` is `id`; `nil` once pruned or cleared.
    ///
    /// - Throws: A decryption error, such as `LoggerCryptoError.keyTemporarilyUnavailable` before the device's
    ///   first unlock.
    public func body(id: String) async throws -> NetworkBody? {
        try await bodyStore.body(id: id)
    }

    /// Deletes every kept body. Call it next to `clearLogs()`, which does not reach them.
    public func clearBodies() async throws {
        try await bodyStore.clear()
    }
}

// MARK: - Recording

/// What one request produced, as the capture paths saw it.
struct HTTPExchange: Sendable {
    var request: URLRequest?
    var requestBody: Data?
    var requestBytes: Int
    var response: URLResponse?
    /// `nil` when not captured.
    var responseBody: Data?
    /// Whether ``responseBody`` holds the whole body; the proxy delegate keeps only a prefix.
    var isResponseBodyComplete = true
    var responseBytes: Int?
    var error: (any Error)?
    var metrics: HTTPMetrics?
    var duration: TimeInterval?
}

extension NetworkLogger {
    /// Off the caller's actor: redacting a large JSON body must not run on the main actor.
    @concurrent
    func record(_ exchange: HTTPExchange, file: String, function: String, line: Int) async {
        // Written before the entry exists, so whoever sees the entry can read the body.
        var bodyID: String?
        if configuration.captureBodies, let body = capturedBody(of: exchange) {
            bodyID = await bodyStore.write(body)
        }
        let url = exchange.request?.url
        let method = exchange.request?.httpMethod ?? "GET"
        let path = url.map { $0.path(percentEncoded: false) }.flatMap { $0.isEmpty ? nil : $0 } ?? "/"
        let response = exchange.response as? HTTPURLResponse
        let duration = exchange.metrics?.duration ?? exchange.duration
        let durationText = duration.map { " (\(Int(($0 * 1_000).rounded())) ms)" } ?? ""

        var metadata: [String: LogMetadataValue] = [
            HTTPLogFields.method: .string(method),
            HTTPLogFields.url: .string(url.map(redacted) ?? ""),
            // What was sent includes the headers URLSession adds: configuration, cookies, `User-Agent`.
            HTTPLogFields.requestHeaders: .dictionary(redacted(exchange.metrics?.sentHeaders
                    ?? exchange.request?.allHTTPHeaderFields ?? [:], base: url)),
            // A streamed body is known only from what was sent.
            HTTPLogFields.requestBytes: .int(max(exchange.requestBytes,
                                                 exchange.metrics?.requestBodyBytesSent ?? 0))
        ]
        if let duration {
            metadata[HTTPLogFields.durationMilliseconds] = .double(Self.milliseconds(duration))
        }
        exchange.metrics?.add(to: &metadata)
        if let bodyID {
            metadata[HTTPLogFields.bodyID] = .string(bodyID)
        }

        let level: LogLevel
        let outcome: String
        var detail = ""
        if let error = exchange.error {
            let nsError = error as NSError
            metadata[HTTPLogFields.error] = .string("\(nsError.domain) \(nsError.code)")
            if Self.isCancellation(error) {
                level = .notice
                outcome = "cancelled"
            } else {
                level = .error
                outcome = "failed"
                detail = ": " + error.localizedDescription
            }
        } else if let response {
            metadata[HTTPLogFields.status] = .int(response.statusCode)
            metadata[HTTPLogFields.responseHeaders] = .dictionary(redacted(response.allHeaderFields,
                                                                           base: response.url ?? url))
            metadata[HTTPLogFields.responseBytes] = .int(exchange.responseBytes ?? 0)
            level = switch response.statusCode {
            case 500...: .error
            case 400...: .warning
            default: .info
            }
            outcome = String(response.statusCode)
        } else {
            level = .error
            outcome = "no response"
        }
        // URLSession's error descriptions are system text; the query never reaches the message.
        let message = LogMessage("\(method) \(path) → \(outcome)\(durationText)\(detail)", privacy: .public)
        // `record` evaluates metadata only for an entry it keeps; a filtered request keeps no body.
        var isRecorded = false
        service.record(level: level, message: message, category: .http, file: file, function: function,
                       line: line, metadata: {
                           isRecorded = true
                           return LogContext.metadata(mergedWith: metadata)
                       }())
        guard let bodyID else { return }
        if isRecorded {
            await bodyStore.commit(id: bodyID)
        } else {
            await bodyStore.remove(id: bodyID)
        }
    }

    static func milliseconds(_ interval: TimeInterval) -> Double {
        (interval * 10_000).rounded() / 10
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}

// MARK: - Redaction

extension NetworkLogger {
    func redacted(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return "" }
        components.user = nil
        components.password = nil
        let query = components.percentEncodedQuery
        components.percentEncodedQuery = nil
        // Never sent to the server, and OAuth implicit flows put tokens there.
        components.percentEncodedFragment = nil
        // Assembled by hand: `URLComponents` would percent-encode `<private>`.
        var text = components.string ?? ""
        if let query {
            text += "?" + redactedFormPairs(query)
        }
        return text
    }

    /// Headers whose value is a URL; OAuth redirects carry tokens in them.
    private static let urlHeaders: Set<String> = ["location", "content-location", "referer"]

    /// `base` resolves a relative URL header, such as a `Location` of `/callback?code=…`.
    func redacted(_ headers: [AnyHashable: Any], base: URL?) -> [String: LogMetadataValue] {
        var result: [String: LogMetadataValue] = [:]
        for case let (name as String, value) in headers {
            let lowercased = name.lowercased()
            if redactedHeaders.contains(lowercased) {
                result[name] = .string(LogPrivacy.privatePlaceholder)
            } else if Self.urlHeaders.contains(lowercased) {
                // A value that is not a URL cannot be redacted key by key, so none of it is kept.
                let url = URL(string: "\(value)", relativeTo: base)?.absoluteURL
                result[name] = .string(url.map(redacted) ?? LogPrivacy.privatePlaceholder)
            } else {
                result[name] = .string("\(value)")
            }
        }
        return result
    }

    /// `name=value&…`, as in a query or a form body, with the values of redacted names replaced. Pairs also split
    /// on `;`, which many servers accept, but `URLComponents` leaves a `;` inside a value unencoded: everything
    /// after a redacted name up to the next `&` is replaced, so no part of its value survives.
    private func redactedFormPairs(_ text: String) -> String {
        text.split(separator: "&", omittingEmptySubsequences: false).map { group in
            var pairs: [String] = []
            for pair in group.split(separator: ";", omittingEmptySubsequences: false) {
                let name = pair.prefix { $0 != "=" }
                let decoded = name.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(name)
                // `user[password]` is how Rails and PHP name nested form fields.
                let parts = decoded.lowercased().split { $0 == "[" || $0 == "]" }
                guard parts.contains(where: { redactedKeys.contains(String($0)) }) else {
                    pairs.append(String(pair))
                    continue
                }
                pairs.append("\(name)=\(LogPrivacy.privatePlaceholder)")
                break
            }
            return pairs.joined(separator: ";")
        }.joined(separator: "&")
    }

    private func capturedBody(of exchange: HTTPExchange) -> NetworkBody? {
        let response = exchange.response as? HTTPURLResponse
        let request = captured(exchange.requestBody, isComplete: true,
                               contentType: exchange.request?.value(forHTTPHeaderField: "Content-Type"))
        let responseBody = captured(exchange.responseBody, isComplete: exchange.isResponseBodyComplete,
                                    contentType: response?.value(forHTTPHeaderField: "Content-Type"))
        guard request != nil || responseBody != nil else { return nil }
        return NetworkBody(request: request?.data, response: responseBody?.data,
                           isRequestTruncated: request?.isTruncated ?? false,
                           isResponseTruncated: responseBody?.isTruncated ?? false)
    }

    /// The body as kept: redacted, then cut to `maxBodyBytes`; `nil` when it is not kept.
    private func captured(_ body: Data?, isComplete: Bool,
                          contentType: String?) -> (data: Data, isTruncated: Bool)? {
        guard let body, !body.isEmpty, let kind = BodyKind(contentType: contentType) else { return nil }
        let redactedBody: Data
        switch kind {
        case .text:
            redactedBody = body
        case .json:
            guard isComplete, body.count <= redactionLimit, let json = redactedJSON(body) else { return nil }
            redactedBody = json
        case .form:
            guard isComplete, body.count <= redactionLimit, let text = String(data: body, encoding: .utf8)
            else { return nil }
            redactedBody = Data(redactedFormPairs(text).utf8)
        }
        let limit = configuration.maxBodyBytes
        let isTruncated = !isComplete || redactedBody.count > limit
        return (Data(redactedBody.prefix(limit)), isTruncated)
    }

    /// The most bytes of a JSON or form body parsed for redaction; larger ones are not kept.
    private var redactionLimit: Int {
        max(configuration.maxBodyBytes, 1 << 20)
    }

    /// The body unchanged when it holds no redacted key, re-encoded with those values replaced otherwise; `nil`
    /// when it cannot be redacted.
    private func redactedJSON(_ body: Data) -> Data? {
        guard !BodyKind.jsonNesting(of: body, exceeds: Self.maxJSONDepth),
              let object = try? JSONSerialization.jsonObject(with: body, options: .fragmentsAllowed)
        else { return nil }
        var didRedact = false
        guard let result = try? redactingJSON(object, depth: 0, didRedact: &didRedact) else { return nil }
        guard didRedact else { return body }
        return try? JSONSerialization.data(withJSONObject: result, options: [.fragmentsAllowed, .sortedKeys])
    }

    private struct Unredactable: Error {}

    /// Depth counts across embedded documents. Each is scanned before Foundation parses it: its parser recurses
    /// up to 512 levels at about 1 KiB of stack each, more than a cooperative thread's 512 KiB.
    private static let maxJSONDepth = 128

    private func redactingJSON(_ value: Any, depth: Int, didRedact: inout Bool) throws -> Any {
        guard depth < Self.maxJSONDepth else { throw Unredactable() }
        if let dictionary = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, child) in dictionary {
                if redactedKeys.contains(key.lowercased()) {
                    result[key] = LogPrivacy.privatePlaceholder
                    didRedact = true
                } else {
                    result[key] = try redactingJSON(child, depth: depth + 1, didRedact: &didRedact)
                }
            }
            return result
        }
        if let array = value as? [Any] {
            return try array.map { try redactingJSON($0, depth: depth + 1, didRedact: &didRedact) }
        }
        // A JSON document carried as a string (an echoed request, a webhook payload) holds keys too.
        if let text = value as? String, let first = text.first(where: { !$0.isWhitespace }),
           first == "{" || first == "[" {
            let bytes = Data(text.utf8)
            guard !BodyKind.jsonNesting(of: bytes, exceeds: Self.maxJSONDepth - depth - 1) else {
                throw Unredactable()
            }
            if let embedded = try? JSONSerialization.jsonObject(with: bytes) {
                var didRedactEmbedded = false
                let result = try redactingJSON(embedded, depth: depth + 1, didRedact: &didRedactEmbedded)
                guard didRedactEmbedded else { return value }
                guard let data = try? JSONSerialization.data(withJSONObject: result, options: .sortedKeys) else {
                    throw Unredactable()
                }
                didRedact = true
                return String(decoding: data, as: UTF8.self)
            }
        }
        return value
    }
}

/// The textual content types whose bodies are kept, and how each is redacted.
package enum BodyKind {
    case text, json, form

    /// Whether `{`/`[` nesting outside string literals goes deeper than `limit`; cheap enough to run before
    /// handing untrusted bytes to a recursive parser. Any NUL byte counts as too deep: UTF-8 JSON never holds one,
    /// and the parser also reads UTF-16 and UTF-32, whose strings this byte-wise scan would misread.
    package static func jsonNesting(of bytes: Data, exceeds limit: Int) -> Bool {
        var depth = 0
        var isInString = false
        var isEscaped = false
        for byte in bytes {
            if byte == 0 {
                return true
            }
            if isInString {
                if isEscaped {
                    isEscaped = false
                } else if byte == UInt8(ascii: "\\") {
                    isEscaped = true
                } else if byte == UInt8(ascii: "\"") {
                    isInString = false
                }
                continue
            }
            switch byte {
            case UInt8(ascii: "\""):
                isInString = true
            case UInt8(ascii: "["), UInt8(ascii: "{"):
                depth += 1
                if depth > limit {
                    return true
                }
            case UInt8(ascii: "]"), UInt8(ascii: "}"):
                depth -= 1
            default:
                break
            }
        }
        return false
    }

    init?(contentType: String?) {
        guard let mime = contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces)
            .lowercased(), let slash = mime.firstIndex(of: "/")
        else { return nil }
        let type = mime[..<slash]
        let subtype = mime[mime.index(after: slash)...]
        if subtype == "json" || subtype.hasSuffix("+json") {
            self = .json
        } else if subtype == "x-www-form-urlencoded" {
            self = .form
        } else if type == "text" || subtype == "xml" || subtype.hasSuffix("+xml") || subtype == "javascript"
            || subtype == "graphql" {
            self = .text
        } else {
            return nil
        }
    }
}
