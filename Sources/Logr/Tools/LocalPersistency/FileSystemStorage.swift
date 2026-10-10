//
//  FileSystemStorage.swift
//  Logr
//
//  Created by martin on 02/11/2025.
//

import Foundation
import OSLog

/// Append-only file storage for encrypted log entries using newline-delimited JSON
/// (one entry per line).
///
/// Appending is O(batch): a `store` seeks to the end of the file and writes only the new
/// lines, so write cost does not grow with the number of already-stored entries (the
/// previous implementation re-read, re-sorted, and rewrote the entire file on every
/// write). Full rewrites happen only during cleanup (`deleteEntries`) and `clear()`.
///
/// Entries are returned oldest first, sorted by timestamp, matching the ``LogRPersistence`` contract and
/// ``SQLiteStorage``; entries with the same timestamp keep the order they were written in.
///
/// Files written by earlier versions (a single JSON array) are migrated to NDJSON, oldest first,
/// the first time the file is opened. An array that cannot be decoded is moved aside to
/// `<fileName>.unreadable-<date>` and logged as a fault; ``clear()`` deletes those files too.
/// A final line left incomplete by a crash is cut on open.
public actor FileSystemStorage: LogRPersistence {
    private let fileURL: URL
    private let write: @Sendable (FileHandle, Data) throws -> Void
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private static let newline = UInt8(ascii: "\n")
    private static let openBracket = UInt8(ascii: "[")
    private static let logger = Logger(subsystem: LogrConfiguration.default.subsystem,
                                       category: LogCategory.persistence.rawValue)

    /// Stores entries in `Application Support/<bundle id>/Logr/<fileName>`.
    ///
    /// The `Logr` directory is created if needed and excluded from backups: entries are encrypted with a
    /// key that never leaves this device, so a restored backup could not be read anyway.
    ///
    /// Logr 1.3 and earlier wrote to `Documents`. When `Documents/<fileName>` exists and the new file
    /// does not, it is moved once; for the default name the old file is `Documents/logr_entries.json`.
    ///
    /// - Parameter fileName: The log file's name. Defaults to `logr_entries.ndjson`.
    /// - Throws: ``LogRErrors/directoryNotFound`` when the system directories cannot be resolved, or a
    ///   file-system error if the directory or file cannot be created, moved or migrated.
    public init(fileName: String = "logr_entries.ndjson") throws {
        let fileManager = FileManager.default
        let applicationSupportURLs = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
              let applicationSupport = applicationSupportURLs.first
        else {
            throw LogRErrors.directoryNotFound
        }
        try self.init(fileName: fileName, documents: documents, applicationSupport: applicationSupport)
    }

    /// The default-location initializer with both system directories injected, so tests never touch the
    /// real ones.
    init(fileName: String, documents: URL, applicationSupport: URL) throws {
        var directory = applicationSupport
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "LogRPersistence")
            .appendingPathComponent("Logr", isDirectory: true)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        // On the directory, not the file: cleanup rewrites the file atomically, which would drop the flag.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)

        let file = directory.appendingPathComponent(fileName)
        let legacyName = fileName == "logr_entries.ndjson" ? "logr_entries.json" : fileName
        let legacyFile = documents.appendingPathComponent(legacyName)
        if !fileManager.fileExists(atPath: file.path), fileManager.fileExists(atPath: legacyFile.path) {
            try fileManager.moveItem(at: legacyFile, to: file)
        }
        try self.init(directory: directory, fileName: fileName)
    }

    /// Stores entries in `fileName` inside `directory`, creating the directory (with any missing
    /// parents) and an empty file when they don't exist yet.
    ///
    /// - Parameters:
    ///   - directory: The directory that holds the log file.
    ///   - fileName: The log file's name within `directory`.
    /// - Throws: A file-system error if the directory or the file cannot be created, or a
    ///   legacy file cannot be migrated.
    public init(directory: URL, fileName: String) throws {
        try self.init(directory: directory, fileName: fileName) { handle, payload in
            try handle.write(contentsOf: payload)
        }
    }

    /// `write` appends a payload; tests replace it to make an append fail partway.
    init(directory: URL, fileName: String, write: @escaping @Sendable (FileHandle, Data) throws -> Void) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent(fileName)
        self.write = write

        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        try Self.prepareFile(at: fileURL, encoder: encoder, decoder: decoder)
    }

    public func store(_ entry: EncryptedLogEntry) async throws {
        try await store([entry])
    }

    public func store(_ entries: [EncryptedLogEntry]) async throws {
        guard !entries.isEmpty else { return }
        let handle = try FileHandle(forUpdating: fileURL)
        defer { try? handle.close() }
        var payload = Data()
        let end = try handle.seekToEnd()
        if end > 0 {
            try handle.seek(toOffset: end - 1)
            // Without this, the first entry would be glued onto an unterminated line and lost.
            if try handle.read(upToCount: 1)?.first != Self.newline {
                payload.append(Self.newline)
            }
        }
        for entry in entries {
            try payload.append(encoder.encode(entry))
            payload.append(Self.newline)
        }
        do {
            try write(handle, payload)
        } catch {
            // All or nothing: a partial batch would leave a fragment, and the writer's retry would
            // duplicate the lines that did land.
            try? handle.truncate(atOffset: end)
            throw error
        }
    }

    public func fetchEntries() async throws -> [EncryptedLogEntry] {
        Self.readEntries(at: fileURL, using: decoder)
    }

    public func deleteEntries(olderThan date: Date) async throws {
        let remaining = Self.readEntries(at: fileURL, using: decoder).filter { $0.timestamp >= date }
        try Self.writeAll(remaining, to: fileURL, using: encoder)
    }

    public func deleteEntries(keepingLatest count: Int) async throws {
        guard count >= 0 else { return }
        let sorted = Self.readEntries(at: fileURL, using: decoder).sorted { $0.timestamp < $1.timestamp }
        try Self.writeAll(Array(sorted.suffix(count)), to: fileURL, using: encoder)
    }

    public func clear() async throws {
        try Data().write(to: fileURL, options: .atomic)
        // Unreadable files moved aside on open still hold encrypted entries.
        let directory = fileURL.deletingLastPathComponent()
        let unreadablePrefix = "\(fileURL.lastPathComponent).unreadable-"
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path)
            where name.hasPrefix(unreadablePrefix) {
            try FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    public func count() async throws -> Int {
        guard let data = try? Data(contentsOf: fileURL) else { return 0 }
        // Each entry occupies exactly one newline-terminated line, so counting the
        // newline bytes avoids decoding every entry.
        return data.count(where: { $0 == Self.newline })
    }
}

private extension FileSystemStorage {
    /// Creates the file if missing, migrates a legacy single-JSON-array file to NDJSON, or cuts an
    /// unterminated final line (a write interrupted by a crash; the partial entry cannot be decoded).
    ///
    /// `static` (like ``readEntries(at:using:)``) so the throwing initializer can call it without
    /// crossing actor isolation, and so a file-mutating helper never depends on — or appears to
    /// escape — the actor's isolation.
    static func prepareFile(at url: URL, encoder: JSONEncoder, decoder: JSONDecoder) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            try Data().write(to: url, options: .atomic)
            return
        }
        // Opening runs at launch, usually on the main thread: peek at two bytes and read the whole file
        // only to migrate or repair it.
        guard let handle = try? FileHandle(forUpdating: url) else { return }
        defer { try? handle.close() }
        guard let first = try? handle.read(upToCount: 1)?.first else { return }
        if first == openBracket {
            guard let data = try? Data(contentsOf: url) else { return }
            try migrateLegacyArray(data, at: url, encoder: encoder, decoder: decoder)
            return
        }
        let end = try handle.seekToEnd()
        try handle.seek(toOffset: end - 1)
        guard try handle.read(upToCount: 1)?.first != newline,
              let data = try? Data(contentsOf: url)
        else {
            return
        }
        let completeLength = data.lastIndex(of: newline).map { data.distance(from: data.startIndex, to: $0) + 1 }
        try handle.truncate(atOffset: UInt64(completeLength ?? 0))
    }

    /// Rewrites a pre-1.2 JSON array, which was stored newest first, as oldest-first NDJSON. An array that
    /// cannot be decoded is moved aside, never overwritten, and the log starts empty.
    ///
    /// Reversed rather than sorted: the file's dates drop fractions of a second, so only the file order
    /// tells entries from the same second apart.
    static func migrateLegacyArray(_ data: Data, at url: URL, encoder: JSONEncoder, decoder: JSONDecoder) throws {
        guard let entries = try? decoder.decode([EncryptedLogEntry].self, from: data) else {
            let stamp = Date().formatted(.iso8601.timeSeparator(.omitted))
            let aside = url.deletingLastPathComponent()
                .appendingPathComponent("\(url.lastPathComponent).unreadable-\(stamp)")
            try FileManager.default.moveItem(at: url, to: aside)
            try Data().write(to: url, options: .atomic)
            logger.fault("Unreadable legacy log file moved to \(aside.lastPathComponent, privacy: .public)")
            return
        }
        try writeAll(entries.reversed(), to: url, using: encoder)
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
        // after a crash) rather than discarding the whole file. Sorted because files converted by
        // 1.2 and 1.3 start with a newest-first block; the sort is stable, so same-second entries
        // keep their file order.
        return data.split(separator: newline, omittingEmptySubsequences: true).compactMap {
            try? decoder.decode(EncryptedLogEntry.self, from: Data($0))
        }
        .sorted { $0.timestamp < $1.timestamp }
    }
}
