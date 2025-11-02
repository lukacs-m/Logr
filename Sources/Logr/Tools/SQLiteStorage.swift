//  
//  SQLiteStorage.swift
//  Logr
//
//  Created by martin on 02/11/2025.
//

import Foundation
import OSLog
import SQLiteData


// Replace with your module types:
public struct EncryptedLogEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let payload: Data
    // add other fields as required
}

public enum LogRErrors: Error {
    case directoryNotFound
    case decodeError
    case missingDataColumn
}

// MARK: - SQLiteLogRStorage

public actor SQLiteLogRStorage: LogRPersistence {
    private let dbQueue: DatabaseQueue
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // MARK: - Init

    /// Create a file-backed database stored in Documents (default fileName).
    public init(fileName: String = "logr_entries.sqlite3") throws {
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        let dbURL = try Self.databaseURL(fileName: fileName)
        // DatabaseQueue will create the file if needed.
        self.dbQueue = try DatabaseQueue(path: dbURL.path)

        // Ensure schema
        try Self.createSchemaIfNeeded(in: dbQueue)
    }

    /// Create from an injected DatabaseQueue (useful for tests or memory DB).
    public init(dbQueue: DatabaseQueue) throws {
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        self.dbQueue = dbQueue
        try Self.createSchemaIfNeeded(in: dbQueue)
    }

    /// Convenience factory for in-memory DB (for unit tests).
    public static func inMemory() throws -> SQLiteLogRStorage {
        let dbQueue = try DatabaseQueue(path: ":memory:")
        return try SQLiteLogRStorage(dbQueue: dbQueue)
    }

    // MARK: - LogRPersistence

    public func store(_ entry: EncryptedLogEntry) async throws {
        let data = try encoder.encode(entry)
        // GRDB sqlite-style write. Use `write` to perform a transactional write.
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            do {
                try dbQueue.write { db in
                    try db.execute(sql: """
                        INSERT INTO log_entries (timestamp, data)
                        VALUES (?, ?)
                        """,
                        arguments: [entry.timestamp.timeIntervalSince1970, data])
                }
                cont.resume()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    public func fetchEntries() async throws -> [EncryptedLogEntry] {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[EncryptedLogEntry], Error>) in
            do {
                var results = [EncryptedLogEntry]()
                try dbQueue.read { db in
                    let rows = try Row.fetchAll(db, sql: """
                        SELECT data FROM log_entries
                        ORDER BY timestamp DESC
                        """)
                    results = try rows.map { row in
                        // Row subscript returns typed values; BLOB -> Data
                        guard let blob: Data = row["data"] else {
                            throw LogRErrors.missingDataColumn
                        }
                        return try decoder.decode(EncryptedLogEntry.self, from: blob)
                    }
                }
                cont.resume(returning: results)
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    public func deleteEntries(olderThan date: Date) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            do {
                try dbQueue.write { db in
                    try db.execute(sql: "DELETE FROM log_entries WHERE timestamp < ?",
                                   arguments: [date.timeIntervalSince1970])
                }
                cont.resume()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    public func deleteEntries(keepingLatest count: Int) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            do {
                try dbQueue.write { db in
                    try db.execute(sql: """
                        DELETE FROM log_entries
                        WHERE id NOT IN (
                            SELECT id FROM log_entries
                            ORDER BY timestamp DESC
                            LIMIT ?
                        )
                        """,
                        arguments: [count])
                }
                cont.resume()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    public func clear() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            do {
                try dbQueue.write { db in
                    try db.execute(sql: "DELETE FROM log_entries")
                }
                cont.resume()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    public func count() async throws -> Int {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int, Error>) in
            do {
                var resultCount = 0
                try dbQueue.read { db in
                    if let row = try Row.fetchOne(db, sql: "SELECT COUNT(*) AS c FROM log_entries"),
                       let value: Int64 = row["c"] { // Row subscript can extract Int64
                        resultCount = Int(value)
                    }
                }
                cont.resume(returning: resultCount)
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}

// MARK: - Private helpers

private extension SQLiteLogRStorage {
    static func databaseURL(fileName: String) throws -> URL {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw LogRErrors.directoryNotFound
        }
        return documents.appendingPathComponent(fileName)
    }

    static func createSchemaIfNeeded(in dbQueue: DatabaseQueue) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS log_entries (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp REAL NOT NULL,
                    data BLOB NOT NULL
                )
                """)
            // create an index for faster sorted queries if needed
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_log_entries_ts ON log_entries(timestamp DESC)")
        }
    }
}




//func appDatabase() throws -> any DatabaseWriter {
//  @Dependency(\.context) var context
//  var configuration = Configuration()
//  #if DEBUG
//    configuration.prepareDatabase { db in
//      db.trace(options: .profile) {
//        if context == .preview {
//          print("\($0.expandedDescription)")
//        } else {
//          logger.debug("\($0.expandedDescription)")
//        }
//      }
//    }
//  #endif
//  let database = try defaultDatabase(configuration: configuration)
//  logger.info("open '\(database.path)'")
//  var migrator = DatabaseMigrator()
//  #if DEBUG
//    migrator.eraseDatabaseOnSchemaChange = true
//  #endif
//  migrator.registerMigration("Create tables") { db in
//    // ...
//  }
//  try migrator.migrate(database)
//  return database
//}
