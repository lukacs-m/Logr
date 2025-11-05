//  
//  SQLiteStorage.swift
//  Logr
//
//  Created by martin on 02/11/2025.
//

import Foundation
import SQLiteData
import Foundation

@Table
struct EncryptedLogEntryDAO: Identifiable, Sendable {
    @Column(primaryKey: true) var id: String
    @Column var data: Data // For storing encrypted log data
    @Column var timestamp: Date
    
    init(id: String, timestamp: Date, data: Data) {
        self.id = id
        self.data = data
        self.timestamp = timestamp
    }
    
    var toEncryptedLogEntry: EncryptedLogEntry {
        EncryptedLogEntry(id: id, timestamp: timestamp, data: data)
    }
}

extension EncryptedLogEntry {
    var toEncryptedLogEntryDAO: EncryptedLogEntryDAO {
        EncryptedLogEntryDAO(id: id, timestamp: timestamp, data: data)
    }
}

public final class LogRepository: LogRPersistence {
    private let database: any DatabaseWriter
    
    public enum DatabaseError: Error {
        case databaseInitializationFailed
        case invalidDatabasePath
    }
    
    /// Initialize with a specific database path
    public init(databasePath: String) throws {
        do {
            // Create parent directory if it doesn't exist
            let fileURL = URL(fileURLWithPath: databasePath)
            let directoryURL = fileURL.deletingLastPathComponent()
            
            if !FileManager.default.fileExists(atPath: directoryURL.path) {
                try FileManager.default.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true
                )
            }
            
            // Create database connection - this will create the file if it doesn't exist
            self.database = try DatabaseQueue(path: databasePath)
            
            // Run migrations to create tables
            try runMigrations()
            
        } catch {
            throw DatabaseError.databaseInitializationFailed
        }
    }
    
    /// Initialize with default database path in Application Support directory
    public convenience init() throws {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw DatabaseError.invalidDatabasePath
        }
        
        let appBundleID = Bundle.main.bundleIdentifier ?? "LogRPersistence"
        let appDirectory = appSupportURL.appendingPathComponent(appBundleID)
        let databasePath = appDirectory
            .appendingPathComponent("logs.sqlite")
            .path
        
        try self.init(databasePath: databasePath)
    }
    
    private func runMigrations() throws {
        var migrator = DatabaseMigrator()
        
        // Initial migration to create the EncryptedLogEntry table
        migrator.registerMigration("create_encrypted_log_entries") { db in
            try db.create(table: "EncryptedLogEntryDAO") { table in
                table.column("id", .text).primaryKey()
                table.column("data", .blob).notNull()
                table.column("timestamp", .date).notNull()
            }
        }
        
        // Add more migrations here as needed in the future
        // migrator.registerMigration("add_new_column") { db in ... }
        
        try migrator.migrate(database)
    }
    
    // MARK: - LogRPersistence Implementation
    
    public func store(_ entry: EncryptedLogEntry) async throws {
        try await database.write { db in
            try EncryptedLogEntryDAO.insert {
                entry.toEncryptedLogEntryDAO
            }
            .execute(db)
        }
    }
    
    public func fetchEntries() async throws -> [EncryptedLogEntry] {
       let results: [EncryptedLogEntryDAO] = try await database.read { db in
            try EncryptedLogEntryDAO
                .order(by: \.timestamp)
                .fetchAll(db)
        }
            return results.map(\.toEncryptedLogEntry)
    }
    
    public func deleteEntries(olderThan date: Date) async throws {
        try await database.write { db in
            try EncryptedLogEntryDAO
                .where { $0.timestamp < date}
                .delete()
                .execute(db)
        }
    }
//    
//    let ids = indices.map { facts.facts[$0].id }
//    try Fact
//      .where { $0.id.in(ids) }
//      .delete()
//      .execute(db)
//    try Item.where { $0.id.in(offsets.map { items[$0].id }) }.delete().execute(db)
//
//    try database.write { db in
//      var ids = reminderRows.map(\.reminder.id)
//      ids.move(fromOffsets: source, toOffset: destination)
//      try Reminder
//        .where { $0.id.in(ids) }
//        .update {
//          let ids = Array(ids.enumerated())
//          let (first, rest) = (ids.first!, ids.dropFirst())
//          $0.position =
//            rest
//            .reduce(Case($0.id).when(first.element, then: first.offset)) { cases, id in
//              cases.when(id.element, then: id.offset)
//            }
//            .else($0.position)
//        }
//        .execute(db)
//    }
//    
    public func deleteEntries(keepingLatest count: Int) async throws {
        try await database.write { db in
            // This uses raw SQL for the complex query
            let sql = """
            DELETE FROM EncryptedLogEntryDAO 
            WHERE id IN (
                SELECT id FROM EncryptedLogEntryDAO 
                ORDER BY timestamp ASC 
                LIMIT (SELECT MAX(0, (SELECT COUNT(*) FROM EncryptedLogEntryDAO) - ?))
            )
            """
            try db.execute(sql: sql, arguments: [count])
        }
    }
    
    public func clear() async throws {
        try await database.write { db in
            try EncryptedLogEntryDAO.all.delete().execute(db)
        }
    }
    
    public func count() async throws -> Int {
        try await database.read { db in
            try EncryptedLogEntryDAO.all.fetchCount(db)
        }
    }
}

//
//
//
//
//
//public enum SQLiteLogRErrors: Error {
//    case directoryNotFound
//    case decodeError
//    case missingDataColumn
//}
//
//// MARK: - SQLiteLogRStorage
//
//public actor SQLiteLogRStorage: LogRPersistence {
//    private let dbQueue: DatabaseQueue
//    private let encoder: JSONEncoder
//    private let decoder: JSONDecoder
//
//    // MARK: - Init
//
//    /// Create a file-backed database stored in Documents (default fileName).
//    public init(fileName: String = "logr_entries.sqlite3") throws {
//        self.encoder = JSONEncoder()
//        self.decoder = JSONDecoder()
//        encoder.dateEncodingStrategy = .iso8601
//        decoder.dateDecodingStrategy = .iso8601
//
//        let dbURL = try Self.databaseURL(fileName: fileName)
//        // DatabaseQueue will create the file if needed.
//        self.dbQueue = try DatabaseQueue(path: dbURL.path)
//
//        // Ensure schema
//        try Self.createSchemaIfNeeded(in: dbQueue)
//    }
//
//    /// Create from an injected DatabaseQueue (useful for tests or memory DB).
//    public init(dbQueue: DatabaseQueue) throws {
//        self.encoder = JSONEncoder()
//        self.decoder = JSONDecoder()
//        encoder.dateEncodingStrategy = .iso8601
//        decoder.dateDecodingStrategy = .iso8601
//
//        self.dbQueue = dbQueue
//        try Self.createSchemaIfNeeded(in: dbQueue)
//    }
//
//    /// Convenience factory for in-memory DB (for unit tests).
//    public static func inMemory() throws -> SQLiteLogRStorage {
//        let dbQueue = try DatabaseQueue(path: ":memory:")
//        return try SQLiteLogRStorage(dbQueue: dbQueue)
//    }
//
//    // MARK: - LogRPersistence
//
//    public func store(_ entry: EncryptedLogEntry) async throws {
//        let data = try encoder.encode(entry)
//        try dbQueue.write { db in
//            try db.execute(sql: """
//                INSERT INTO log_entries (timestamp, data)
//                VALUES (?, ?)
//                """,
//                arguments: [entry.timestamp.timeIntervalSince1970, data])
//        }
////        // GRDB sqlite-style write. Use `write` to perform a transactional write.
////        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
////            do {
////                try dbQueue.write { db in
////                    try db.execute(sql: """
////                        INSERT INTO log_entries (timestamp, data)
////                        VALUES (?, ?)
////                        """,
////                        arguments: [entry.timestamp.timeIntervalSince1970, data])
////                }
////                cont.resume()
////            } catch {
////                cont.resume(throwing: error)
////            }
////        }
//    }
//
//    public func fetchEntries() async throws -> [EncryptedLogEntry] {
//        var results = [EncryptedLogEntry]()
//        try dbQueue.read { db in
//            let rows = try Row.fetchAll(db, sql: """
//                SELECT data FROM log_entries
//                ORDER BY timestamp DESC
//                """)
//            results = try rows.map { row in
//                // Row subscript returns typed values; BLOB -> Data
//                guard let blob: Data = row["data"] else {
//                    throw LogRErrors.missingDataColumn
//                }
//                return try decoder.decode(EncryptedLogEntry.self, from: blob)
//            }
//        }
////        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[EncryptedLogEntry], Error>) in
////            do {
////                var results = [EncryptedLogEntry]()
////                try dbQueue.read { db in
////                    let rows = try Row.fetchAll(db, sql: """
////                        SELECT data FROM log_entries
////                        ORDER BY timestamp DESC
////                        """)
////                    results = try rows.map { row in
////                        // Row subscript returns typed values; BLOB -> Data
////                        guard let blob: Data = row["data"] else {
////                            throw LogRErrors.missingDataColumn
////                        }
////                        return try decoder.decode(EncryptedLogEntry.self, from: blob)
////                    }
////                }
////                cont.resume(returning: results)
////            } catch {
////                cont.resume(throwing: error)
////            }
////        }
//    }
//
//    public func deleteEntries(olderThan date: Date) async throws {
//        try dbQueue.write { db in
//            try db.execute(sql: "DELETE FROM log_entries WHERE timestamp < ?",
//                           arguments: [date.timeIntervalSince1970])
//        }
////        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
////            do {
////                try dbQueue.write { db in
////                    try db.execute(sql: "DELETE FROM log_entries WHERE timestamp < ?",
////                                   arguments: [date.timeIntervalSince1970])
////                }
////                cont.resume()
////            } catch {
////                cont.resume(throwing: error)
////            }
////        }
//    }
//
//    public func deleteEntries(keepingLatest count: Int) async throws {
//        try dbQueue.write { db in
//            try db.execute(sql: """
//                DELETE FROM log_entries
//                WHERE id NOT IN (
//                    SELECT id FROM log_entries
//                    ORDER BY timestamp DESC
//                    LIMIT ?
//                )
//                """,
//                arguments: [count])
//        }
////        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
////            do {
////         
////                cont.resume()
////            } catch {
////                cont.resume(throwing: error)
////            }
////        }
//    }
//
//    public func clear() async throws {
//        try dbQueue.write { db in
//            try db.execute(sql: "DELETE FROM log_entries")
//        }
////        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
////            do {
////             
////                cont.resume()
////            } catch {
////                cont.resume(throwing: error)
////            }
////        }
//    }
//
//    public func count() async throws -> Int {
//        var resultCount = 0
//        try dbQueue.read { db in
//            if let row = try Row.fetchOne(db, sql: "SELECT COUNT(*) AS c FROM log_entries"),
//               let value: Int64 = row["c"] { // Row subscript can extract Int64
//                resultCount = Int(value)
//            }
//        }
////        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int, Error>) in
////            do {
////         
////                cont.resume(returning: resultCount)
////            } catch {
////                cont.resume(throwing: error)
////            }
////        }
//    }
//}
//
//// MARK: - Private helpers
//
//private extension SQLiteLogRStorage {
//    static func databaseURL(fileName: String) throws -> URL {
//        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
//            throw LogRErrors.directoryNotFound
//        }
//        return documents.appendingPathComponent(fileName)
//    }
//
//    static func createSchemaIfNeeded(in dbQueue: DatabaseQueue) throws {
//        try dbQueue.write { db in
//            try db.execute(sql: """
//                CREATE TABLE IF NOT EXISTS log_entries (
//                    id INTEGER PRIMARY KEY AUTOINCREMENT,
//                    timestamp REAL NOT NULL,
//                    data BLOB NOT NULL
//                )
//                """)
//            // create an index for faster sorted queries if needed
//            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_log_entries_ts ON log_entries(timestamp DESC)")
//        }
//    }
//}
//
//


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
