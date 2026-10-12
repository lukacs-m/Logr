//
//  SQLiteStorage.swift
//  Logr
//
//  Created by martin on 02/11/2025.
//

import Foundation
import SQLite3

/// Stores encrypted log entries in an SQLite database, using the SQLite library that ships with the OS.
///
/// Entries are returned oldest first, sorted by timestamp; entries with the same timestamp keep the order they
/// were written in. A batch is written in one transaction. Storing an entry whose `id` is already stored keeps
/// the stored entry and drops the new one.
///
/// Databases written by Logr 1.x open unchanged.
public actor SQLiteStorage: LogRPersistence {
    /// An SQLite failure.
    public struct Error: Swift.Error, CustomStringConvertible {
        /// The SQLite result code, such as `SQLITE_CANTOPEN` (14).
        public let code: Int32
        /// SQLite's description of the failure, from `sqlite3_errmsg`.
        public let message: String

        public var description: String {
            "SQLite error \(code): \(message)"
        }
    }

    private let connection: Connection

    /// Opens the database at `databasePath`, creating the file and any missing parent directories.
    ///
    /// - Parameter databasePath: The database file's path.
    /// - Throws: ``Error`` if the database cannot be opened or its table created, or a file-system error if
    ///   the parent directory cannot be created.
    public init(databasePath: String) throws {
        let directory = URL(fileURLWithPath: databasePath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let connection = try Connection(path: databasePath)
        // When two connections set up the same file at once, SQLite reports busy without waiting (waiting could
        // deadlock), so the setup is retried for as long as the busy timeout would have waited.
        let deadline = ContinuousClock.now + .seconds(1)
        while true {
            do {
                // Logr 1.x's schema, which it created through GRDB; its `grdb_migrations` table is left alone.
                try connection.execute("""
                PRAGMA journal_mode = WAL;
                CREATE TABLE IF NOT EXISTS EncryptedLogEntryDAO (
                    id TEXT PRIMARY KEY, data BLOB NOT NULL, timestamp DOUBLE NOT NULL
                );
                CREATE INDEX IF NOT EXISTS EncryptedLogEntryDAO_timestamp ON EncryptedLogEntryDAO(timestamp);
                """)
                break
            } catch let error as Error where error.code == SQLITE_BUSY && ContinuousClock.now < deadline {
                sqlite3_sleep(10)
            }
        }
        self.connection = connection
    }

    /// Opens the database at `Application Support/<bundle id>/logs.sqlite`.
    ///
    /// The database and its write-ahead log are excluded from backups: entries are encrypted with a key that
    /// never leaves this device, so a restored backup could not be read anyway.
    ///
    /// - Throws: ``LogRErrors/directoryNotFound`` when Application Support cannot be resolved, ``Error`` if the
    ///   database cannot be opened, or a file-system error if a directory cannot be created.
    public init() throws {
        guard let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                                in: .userDomainMask).first
        else {
            throw LogRErrors.directoryNotFound
        }
        try self.init(applicationSupport: applicationSupport)
    }

    /// The default-path initializer with Application Support injected, so tests never touch the real one.
    init(applicationSupport: URL) throws {
        let databasePath = applicationSupport
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "LogRPersistence")
            .appendingPathComponent("logs.sqlite").path
        try self.init(databasePath: databasePath)

        // A restored `-wal` without its database would be replayed into the next, new database.
        // SQLite deletes the `-wal` and `-shm` files when the last connection closes, so mark them on every open.
        for suffix in ["", "-wal", "-shm"] {
            var file = URL(fileURLWithPath: databasePath + suffix)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try file.setResourceValues(values)
        }
    }
}

// MARK: - LogRPersistence

public extension SQLiteStorage {
    func store(_ entry: EncryptedLogEntry) async throws {
        try insert([entry])
    }

    func store(_ entries: [EncryptedLogEntry]) async throws {
        try insert(entries)
    }

    func fetchEntries() async throws -> [EncryptedLogEntry] {
        try fetch("SELECT id, data, timestamp FROM EncryptedLogEntryDAO ORDER BY timestamp, rowid")
    }

    func fetchEntries(limit: Int?) async throws -> [EncryptedLogEntry] {
        guard let limit else { return try await fetchEntries() }
        let newestFirst = try fetch("""
        SELECT id, data, timestamp FROM EncryptedLogEntryDAO ORDER BY timestamp DESC, rowid DESC LIMIT ?
        """) { sqlite3_bind_int64($0, 1, Int64(limit)) }
        return newestFirst.reversed()
    }

    func deleteEntries(olderThan date: Date) async throws {
        try connection.run("DELETE FROM EncryptedLogEntryDAO WHERE timestamp < ?") {
            sqlite3_bind_double($0, 1, date.timeIntervalSince1970)
        }
    }

    func deleteEntries(keepingLatest count: Int) async throws {
        try connection.run("""
        DELETE FROM EncryptedLogEntryDAO WHERE rowid NOT IN (
            SELECT rowid FROM EncryptedLogEntryDAO ORDER BY timestamp DESC, rowid DESC LIMIT ?
        )
        """) { sqlite3_bind_int64($0, 1, Int64(count)) }
    }

    func clear() async throws {
        try connection.run("DELETE FROM EncryptedLogEntryDAO")
    }

    func count() async throws -> Int {
        var count = 0
        try connection.step("SELECT COUNT(*) FROM EncryptedLogEntryDAO") { row in
            count = Int(sqlite3_column_int64(row, 0))
        }
        return count
    }
}

private extension SQLiteStorage {
    static let insertSQL = "INSERT OR IGNORE INTO EncryptedLogEntryDAO (id, data, timestamp) VALUES (?, ?, ?)"

    func insert(_ entries: [EncryptedLogEntry]) throws {
        guard !entries.isEmpty else { return }
        try connection.run("BEGIN IMMEDIATE")
        do {
            for entry in entries {
                try connection.run(Self.insertSQL) { statement in
                    sqlite3_bind_text(statement, 1, entry.id, Int32(entry.id.utf8.count), Connection.transient)
                    if entry.data.isEmpty {
                        // An empty buffer may have no base address, and a null pointer binds NULL, which the
                        // NOT NULL column rejects and `OR IGNORE` would turn into a silently dropped row.
                        sqlite3_bind_zeroblob(statement, 2, 0)
                    } else {
                        _ = entry.data.withUnsafeBytes {
                            sqlite3_bind_blob64(statement, 2, $0.baseAddress, UInt64($0.count),
                                                Connection.transient)
                        }
                    }
                    sqlite3_bind_double(statement, 3, entry.timestamp.timeIntervalSince1970)
                }
            }
            try connection.run("COMMIT")
        } catch {
            // Fails harmlessly when SQLite already rolled back on its own.
            try? connection.run("ROLLBACK")
            throw error
        }
    }

    func fetch(_ sql: String, bind: (OpaquePointer) -> Void = { _ in }) throws -> [EncryptedLogEntry] {
        var entries: [EncryptedLogEntry] = []
        try connection.step(sql, bind: bind) { row in
            let id = String(decoding: UnsafeRawBufferPointer(start: sqlite3_column_text(row, 0),
                                                             count: Int(sqlite3_column_bytes(row, 0))),
                            as: UTF8.self)
            // SQLite returns no pointer for an empty blob.
            let data = sqlite3_column_blob(row, 1)
                .map { Data(bytes: $0, count: Int(sqlite3_column_bytes(row, 1))) }
                ?? Data()
            let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(row, 2))
            entries.append(EncryptedLogEntry(id: id, timestamp: timestamp, data: data))
        }
        return entries
    }
}

// MARK: - Connection

/// The database handle and its cached statements, closed in `deinit`. A separate class because an actor's
/// `deinit` cannot touch non-Sendable state such as these pointers.
private final class Connection {
    /// Tells SQLite to copy bound text and blobs before the call returns.
    static var transient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    private let handle: OpaquePointer
    private var statements: [String: OpaquePointer] = [:]

    init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let status = sqlite3_open_v2(path, &handle, flags, nil)
        guard status == SQLITE_OK, let handle else {
            // No handle only when SQLite is out of memory, which is what `sqlite3_errmsg(nil)` reports.
            let message = String(cString: sqlite3_errmsg(handle))
            // SQLite returns a handle even when opening fails, and it must still be closed.
            sqlite3_close_v2(handle)
            throw SQLiteStorage.Error(code: status, message: message)
        }
        self.handle = handle
        // Another connection to the same file (a second storage, an app extension) may hold the write lock.
        sqlite3_busy_timeout(handle, 1_000)
    }

    deinit {
        for statement in statements.values {
            sqlite3_finalize(statement)
        }
        sqlite3_close_v2(handle)
    }

    func execute(_ sql: String) throws {
        let status = sqlite3_exec(handle, sql, nil, nil, nil)
        guard status == SQLITE_OK else { throw error(status) }
    }

    func run(_ sql: String, bind: (OpaquePointer) -> Void = { _ in }) throws {
        try step(sql, bind: bind) { _ in }
    }

    /// Runs a cached statement to completion, calling `row` for each result row.
    func step(_ sql: String, bind: (OpaquePointer) -> Void = { _ in }, row: (OpaquePointer) -> Void) throws {
        let statement = try prepared(sql)
        defer {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
        bind(statement)
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE {
                return
            }
            guard status == SQLITE_ROW else { throw error(status) }
            row(statement)
        }
    }

    private func prepared(_ sql: String) throws -> OpaquePointer {
        if let statement = statements[sql] {
            return statement
        }
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v3(handle, sql, -1, UInt32(SQLITE_PREPARE_PERSISTENT), &statement, nil)
        guard status == SQLITE_OK, let statement else { throw error(status) }
        statements[sql] = statement
        return statement
    }

    private func error(_ status: Int32) -> SQLiteStorage.Error {
        SQLiteStorage.Error(code: status, message: String(cString: sqlite3_errmsg(handle)))
    }
}
