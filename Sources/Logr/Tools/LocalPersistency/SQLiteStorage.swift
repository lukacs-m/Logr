//
//  SQLiteStorage.swift
//  Logr
//
//  Created by martin on 02/11/2025.
//

import Foundation
import SQLiteData

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
                try FileManager.default.createDirectory(at: directoryURL,
                                                        withIntermediateDirectories: true)
            }

            // Create database connection - this will create the file if it doesn't exist
            database = try DatabaseQueue(path: databasePath)

            // Run migrations to create tables
            try runMigrations()

        } catch {
            throw DatabaseError.databaseInitializationFailed
        }
    }

    /// Initialize with default database path in Application Support directory
    public convenience init() throws {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask).first else {
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
                table.column("timestamp", .double).notNull()
            }
        }

        try migrator.migrate(database)
    }
}

// MARK: - LogRPersistence Implementation / CRUD actions

public extension LogRepository {
    func store(_ entry: EncryptedLogEntry) async throws {
        try await database.write { db in
            try EncryptedLogEntryDAO.insert {
                entry.toEncryptedLogEntryDAO
            }
            .execute(db)
        }
    }

    func fetchEntries() async throws -> [EncryptedLogEntry] {
        let results: [EncryptedLogEntryDAO] = try await database.read { db in
            try EncryptedLogEntryDAO
                .order(by: \.timestamp)
                .fetchAll(db)
        }
        return results.map(\.toEncryptedLogEntry)
    }

    func deleteEntries(olderThan date: Date) async throws {
        try await database.write { db in
            try EncryptedLogEntryDAO
                .where { $0.timestamp < date.timeIntervalSince1970 }
                .delete()
                .execute(db)
        }
    }

    func deleteEntries(keepingLatest count: Int) async throws {
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

    func clear() async throws {
        try await database.write { db in
            try EncryptedLogEntryDAO.all.delete().execute(db)
        }
    }

    func count() async throws -> Int {
        try await database.read { db in
            try EncryptedLogEntryDAO.all.fetchCount(db)
        }
    }
}
