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

    @Test("The default database is excluded from backups")
    func testDefaultDatabaseIsExcludedFromBackup() async throws {
        let repository = try SQLiteStorage(applicationSupport: directory.url)
        #expect(try await repository.count() == 0)

        let databaseURL = directory.url.appendingPathComponent(Bundle.main.bundleIdentifier ?? "LogRPersistence")
            .appendingPathComponent("logs.sqlite")
        #expect(try databaseURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
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
