//
//  FileSystemStorage.swift
//  Logr
//
//  Created by martin on 02/11/2025.
//

import Foundation

/// Append-only file storage for encrypted log entries using newline-delimited JSON
/// (one entry per line).
///
/// Appending is O(batch): a `store` seeks to the end of the file and writes only the new
/// lines, so write cost does not grow with the number of already-stored entries (the
/// previous implementation re-read, re-sorted, and rewrote the entire file on every
/// write). Full rewrites happen only during cleanup (`deleteEntries`) and `clear()`.
///
/// Entries are returned in insertion order, which — because the writer persists entries in
/// the order they are logged — is chronological (oldest first), matching the
/// ``LogRPersistence`` contract and ``SQLiteStorage``.
///
/// Files written by earlier versions (a single JSON array) are migrated to NDJSON the
/// first time the file is opened.
public actor FileSystemStorage: LogRPersistence {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private static let newline = UInt8(ascii: "\n")
    private static let openBracket = UInt8(ascii: "[")

    public init(fileName: String = "logr_entries.json") throws {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else {
            throw LogRErrors.directoryNotFound
        }
        fileURL = documentsPath.appendingPathComponent(fileName)

        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        try Self.prepareFile(at: fileURL, encoder: encoder, decoder: decoder)
    }

    public func store(_ entry: EncryptedLogEntry) async throws {
        try await store([entry])
    }

    public func store(_ newEntries: [EncryptedLogEntry]) async throws {
        guard !newEntries.isEmpty else { return }
        var payload = Data()
        for entry in newEntries {
            try payload.append(encoder.encode(entry))
            payload.append(Self.newline)
        }
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: payload)
    }

    public func fetchEntries() async throws -> [EncryptedLogEntry] {
        Self.readEntries(at: fileURL, using: decoder)
    }

    public func deleteEntries(olderThan date: Date) async throws {
        let remaining = Self.readEntries(at: fileURL, using: decoder).filter { $0.timestamp > date }
        try Self.writeAll(remaining, to: fileURL, using: encoder)
    }

    public func deleteEntries(keepingLatest count: Int) async throws {
        guard count >= 0 else { return }
        let sorted = Self.readEntries(at: fileURL, using: decoder).sorted { $0.timestamp < $1.timestamp }
        try Self.writeAll(Array(sorted.suffix(count)), to: fileURL, using: encoder)
    }

    public func clear() async throws {
        try Data().write(to: fileURL, options: .atomic)
    }

    public func count() async throws -> Int {
        guard let data = try? Data(contentsOf: fileURL) else { return 0 }
        // Each entry occupies exactly one newline-terminated line, so counting the
        // newline bytes avoids decoding every entry.
        return data.count(where: { $0 == Self.newline })
    }
}

private extension FileSystemStorage {
    /// Creates the file if missing, or migrates a legacy single-JSON-array file to NDJSON.
    ///
    /// `static` (like ``readEntries(at:using:)``) so the throwing initializer can call it without
    /// crossing actor isolation, and so a file-mutating helper never depends on — or appears to
    /// escape — the actor's isolation.
    static func prepareFile(at url: URL, encoder: JSONEncoder, decoder: JSONDecoder) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            try Data().write(to: url, options: .atomic)
            return
        }
        guard let data = try? Data(contentsOf: url), data.first == openBracket else {
            return // already NDJSON (or empty)
        }
        // Legacy format detected: rewrite the JSON array as NDJSON.
        let entries = (try? decoder.decode([EncryptedLogEntry].self, from: data)) ?? []
        try writeAll(entries, to: url, using: encoder)
    }

    /// Rewrites the whole file as NDJSON. Used only by migration and cleanup.
    static func writeAll(_ entries: [EncryptedLogEntry], to url: URL, using encoder: JSONEncoder) throws {
        var data = Data()
        for entry in entries {
            try data.append(encoder.encode(entry))
            data.append(newline)
        }
        try data.write(to: url, options: .atomic)
    }

    static func readEntries(at url: URL, using decoder: JSONDecoder) -> [EncryptedLogEntry] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [] }
        // Legacy format: a single JSON array (begins with '[').
        if data.first == openBracket {
            return (try? decoder.decode([EncryptedLogEntry].self, from: data)) ?? []
        }
        // NDJSON: one entry per line. Skip any unreadable line (e.g. a partial write
        // after a crash) rather than discarding the whole file.
        return data.split(separator: newline, omittingEmptySubsequences: true).compactMap {
            try? decoder.decode(EncryptedLogEntry.self, from: Data($0))
        }
    }
}
