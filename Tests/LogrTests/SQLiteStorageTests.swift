import Testing
@testable import Logr
import Foundation

/// Behaviour specific to the SQLite database. The shared `LogRPersistence` contract is covered by
/// `StorageConformanceTests`.
@Suite("SQLite Storage Tests")
struct SQLiteStorageTests {
    private let directory: TemporaryDirectory

    init() throws {
        directory = try TemporaryDirectory()
    }

    @Test("Test database initialization creates parent directory")
    func testDatabaseInitializationCreatesParentDirectory() async throws {
        let testDBPath = directory.url.appendingPathComponent("nested/test.sqlite").path

        let repository = try SQLiteStorage(databasePath: testDBPath)
        let count = try await repository.count()

        #expect(count == 0)
        #expect(FileManager.default.fileExists(atPath: testDBPath))
    }

    @Test("The default database and its write-ahead log are excluded from backups")
    func testDefaultDatabaseIsExcludedFromBackup() async throws {
        let repository = try SQLiteStorage(applicationSupport: directory.url)
        #expect(try await repository.count() == 0)

        let databasePath = directory.url.appendingPathComponent(Bundle.main.bundleIdentifier ?? "LogRPersistence")
            .appendingPathComponent("logs.sqlite").path
        for path in [databasePath, databasePath + "-wal", databasePath + "-shm"] {
            let values = try URL(fileURLWithPath: path).resourceValues(forKeys: [.isExcludedFromBackupKey])
            #expect(values.isExcludedFromBackup == true, "\(path)")
        }
    }

    @Test func openingFailureSurfacesTheSQLiteError() throws {
        // A directory cannot be opened as a database.
        let error = try #require(throws: SQLiteStorage.Error.self) {
            try SQLiteStorage(databasePath: directory.url.path)
        }

        #expect(error.code == 14) // SQLITE_CANTOPEN
        #expect(!error.message.isEmpty)
    }

    @Test func batchWithAStoredIDKeepsTheStoredEntryAndStoresTheRest() async throws {
        let repository = try SQLiteStorage(databasePath: directory.url.appendingPathComponent("test.sqlite").path)
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let original = EncryptedLogEntry(id: "a", timestamp: now, data: Data("original".utf8))
        try await repository.store(original)

        try await repository.store([
            EncryptedLogEntry(id: "a", timestamp: now, data: Data("duplicate".utf8)),
            EncryptedLogEntry(id: "b", timestamp: now.addingTimeInterval(1), data: Data("b".utf8))
        ])

        let entries = try await repository.fetchEntries()
        #expect(entries.map(\.id) == ["a", "b"])
        #expect(entries.first == original)
    }

    @Test func twoStoragesOnTheSameFileKeepEveryWrite() async throws {
        let path = directory.url.appendingPathComponent("shared.sqlite").path
        let first = try SQLiteStorage(databasePath: path)
        let second = try SQLiteStorage(databasePath: path)
        let start = Date(timeIntervalSince1970: 1_767_225_600)

        try await withThrowingTaskGroup { group in
            for (prefix, storage) in [("first", first), ("second", second)] {
                for batch in 0 ..< 20 {
                    let entries = (0 ..< 50).map { index in
                        EncryptedLogEntry(id: "\(prefix)-\(batch)-\(index)",
                                          timestamp: start.addingTimeInterval(TimeInterval(batch * 50 + index)),
                                          data: Data(prefix.utf8))
                    }
                    group.addTask { try await storage.store(entries) }
                }
            }
            try await group.waitForAll()
        }

        #expect(try await first.count() == 2000)
        #expect(try await second.count() == 2000)
    }

    /// An app and its extension may set up a new database, or switch a Logr 1.x one to WAL, at the same moment.
    @Test(arguments: [nil, "legacy.sqlite"] as [String?])
    func storagesSettingUpOneDatabaseTogetherAllOpen(fixture: String?) async throws {
        for attempt in 0 ..< 50 {
            let url = directory.url.appendingPathComponent("\(attempt).sqlite")
            if let fixture {
                try FileManager.default.copyItem(at: LegacyFixtures.url(fixture), to: url)
            }
            try await withThrowingTaskGroup { group in
                for _ in 0 ..< 3 {
                    group.addTask { _ = try await SQLiteStorage(databasePath: url.path).count() }
                }
                try await group.waitForAll()
            }
        }
    }

    @Test("Test fetch entries are ordered by timestamp, not insertion")
    func testFetchEntriesOrderedByTimestamp() async throws {
        let repository = try SQLiteStorage(databasePath: directory.url.appendingPathComponent("test.sqlite").path)

        let now = Date()
        let entry1 = EncryptedLogEntry(
            id: "entry-1",
            timestamp: now.addingTimeInterval(-100),
            data: Data("old".utf8)
        )
        let entry2 = EncryptedLogEntry(
            id: "entry-2",
            timestamp: now,
            data: Data("new".utf8)
        )

        try await repository.store(entry2)
        try await repository.store(entry1)

        let entries = try await repository.fetchEntries()

        #expect(entries.count == 2)
        // Should be ordered by timestamp (ascending)
        #expect(entries[0].id == "entry-1")
        #expect(entries[1].id == "entry-2")
    }
}
