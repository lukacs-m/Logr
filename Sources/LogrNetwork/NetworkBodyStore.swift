//
//  NetworkBodyStore.swift
//  LogrNetwork
//

import Foundation
import Logr
import OSLog

/// The bodies ``NetworkLogger`` captured for one request.
///
/// A body is `nil` when the request had none, when its content type is not textual, or when a JSON or form body
/// could not be redacted. Each holds at most ``NetworkLoggerConfiguration/maxBodyBytes``.
public struct NetworkBody: Sendable, Codable, Hashable {
    /// The request body: JSON and form bodies with the keys in ``NetworkLoggerConfiguration/redactedKeys``
    /// redacted, other textual bodies as sent.
    public let request: Data?
    /// The response body: JSON and form bodies with the keys in ``NetworkLoggerConfiguration/redactedKeys``
    /// redacted, other textual bodies as received.
    public let response: Data?
    /// Whether ``request`` was cut at ``NetworkLoggerConfiguration/maxBodyBytes``.
    public let isRequestTruncated: Bool
    /// Whether ``response`` was cut at ``NetworkLoggerConfiguration/maxBodyBytes``.
    public let isResponseTruncated: Bool

    package init(request: Data?, response: Data?, isRequestTruncated: Bool, isResponseTruncated: Bool) {
        self.request = request
        self.response = response
        self.isRequestTruncated = isRequestTruncated
        self.isResponseTruncated = isResponseTruncated
    }
}

/// One encrypted file per request, named so that names sort oldest first, pruned to the newest `limit`.
actor NetworkBodyStore {
    private let directory: URL
    private let crypto: any LoggerCryptoServicing
    private let limit: Int
    private var lastStamp: UInt64 = 0
    /// Written but not yet kept or removed: neither counted nor pruned, so another request's prune cannot take a
    /// kept body's place for one that is about to go.
    private var pending: Set<String> = []
    private var isPrepared = false

    private static let logger = Logger(subsystem: "Logr", category: LogCategory.http.rawValue)

    init(directory: URL, crypto: any LoggerCryptoServicing, limit: Int) {
        self.directory = directory
        self.crypto = crypto
        self.limit = limit
    }

    /// Encrypts and writes `body`, or `nil` if it cannot. Follow with ``commit(id:)`` or ``remove(id:)``.
    func write(_ body: NetworkBody) -> String? {
        do {
            try prepare()
            let id = nextID()
            try crypto.symmetricEncrypt(object: body).write(to: directory.appendingPathComponent(id),
                                                            options: .atomic)
            pending.insert(id)
            return id
        } catch {
            Self.logger.error("Could not store an HTTP body: \(error, privacy: .public)")
            return nil
        }
    }

    /// Keeps a written body, then deletes all but the newest `limit` kept bodies; a failure only delays that to
    /// the next commit.
    func commit(id: String) {
        pending.remove(id)
        do {
            for id in try storedIDs().filter({ !pending.contains($0) }).sorted().dropLast(limit) {
                try FileManager.default.removeItem(at: directory.appendingPathComponent(id))
            }
        } catch {
            Self.logger.error("Could not prune HTTP bodies: \(error, privacy: .public)")
        }
    }

    /// Deletes a body whose entry was not recorded.
    func remove(id: String) {
        pending.remove(id)
        guard Self.isValid(id) else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(id))
    }

    func body(id: String) throws -> NetworkBody? {
        guard Self.isValid(id) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: directory.appendingPathComponent(id))
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
        return try crypto.symmetricDecrypt(encryptedData: data)
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        for id in try storedIDs() {
            try FileManager.default.removeItem(at: directory.appendingPathComponent(id))
        }
    }

    private func prepare() throws {
        guard !isPrepared else { return }
        var directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Encrypted with a key that never leaves the device, so a restored backup could not be read anyway.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        // Names must keep sorting oldest first even when the clock is now behind the newest one.
        lastStamp = try storedIDs().compactMap { UInt64($0.prefix(20)) }.max() ?? 0
        isPrepared = true
    }

    /// Zero-padded nanoseconds, kept increasing within the process, then a UUID against other writers.
    private func nextID() -> String {
        lastStamp = max(clock_gettime_nsec_np(CLOCK_REALTIME), lastStamp == .max ? .max : lastStamp + 1)
        let stamp = String(lastStamp)
        return String(repeating: "0", count: max(0, 20 - stamp.count)) + stamp + "-" + UUID().uuidString
    }

    private func storedIDs() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter(Self.isValid)
    }

    /// Ids come from entries and callers; anything else must never become a path.
    private static func isValid(_ id: String) -> Bool {
        let parts = id.split(separator: "-", maxSplits: 1)
        return parts.count == 2 && parts[0].count == 20 && parts[0].allSatisfy(\.isASCIIDigit)
            && UInt64(parts[0]) != nil
            && UUID(uuidString: String(parts[1])) != nil
    }
}

private extension Character {
    var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}
