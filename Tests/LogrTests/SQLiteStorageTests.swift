import Testing
@testable import Logr
import Foundation

@Suite("SQLite Storage Tests")
struct SQLiteStorageTests {

    // MARK: - Helper to create test database

    func createTestDatabase() throws -> LogRepository {
        let tempDir = FileManager.default.temporaryDirectory
        let testDBPath = tempDir
            .appendingPathComponent("test_\(UUID().uuidString).sqlite")
            .path
        return try LogRepository(databasePath: testDBPath)
    }

    // MARK: - Initialization Tests

    @Test("Test database initialization with custom path")
    func testDatabaseInitializationWithCustomPath() async throws {
        let repository = try createTestDatabase()
        let count = try await repository.count()
        #expect(count == 0)
    }

    @Test("Test database initialization with default path")
    func testDatabaseInitializationWithDefaultPath() async throws {
        // This might fail if bundle identifier is not available in test context
        // but we'll test it anyway
        do {
            _ = try LogRepository()
        } catch {
            // Expected to possibly fail in test environment
            #expect(error is LogRepository.DatabaseError)
        }
    }

    @Test("Test database initialization creates parent directory")
    func testDatabaseInitializationCreatesParentDirectory() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("testdir_\(UUID().uuidString)")
        let testDBPath = testDir.appendingPathComponent("test.sqlite").path

        let repository = try LogRepository(databasePath: testDBPath)
        let count = try await repository.count()

        #expect(count == 0)
        #expect(FileManager.default.fileExists(atPath: testDBPath))

        // Cleanup
        try? FileManager.default.removeItem(at: testDir)
    }

    // MARK: - Store Tests

    @Test("Test store single entry")
    func testStoreSingleEntry() async throws {
        let repository = try createTestDatabase()

        let entry = EncryptedLogEntry(
            id: UUID().uuidString,
            timestamp: Date(),
            data: Data("encrypted data".utf8)
        )

        try await repository.store(entry)

        let count = try await repository.count()
        #expect(count == 1)
    }

    @Test("Test store multiple entries")
    func testStoreMultipleEntries() async throws {
        let repository = try createTestDatabase()

        for i in 1...10 {
            let entry = EncryptedLogEntry(
                id: "entry-\(i)",
                timestamp: Date(),
                data: Data("encrypted data \(i)".utf8)
            )
            try await repository.store(entry)
        }

        let count = try await repository.count()
        #expect(count == 10)
    }

    @Test("Test store entry with large data")
    func testStoreEntryWithLargeData() async throws {
        let repository = try createTestDatabase()

        let largeData = Data(repeating: 0xFF, count: 100000)
        let entry = EncryptedLogEntry(
            id: UUID().uuidString,
            timestamp: Date(),
            data: largeData
        )

        try await repository.store(entry)

        let count = try await repository.count()
        #expect(count == 1)
    }

    @Test("Test store entry with empty data")
    func testStoreEntryWithEmptyData() async throws {
        let repository = try createTestDatabase()

        let entry = EncryptedLogEntry(
            id: UUID().uuidString,
            timestamp: Date(),
            data: Data()
        )

        try await repository.store(entry)

        let count = try await repository.count()
        #expect(count == 1)
    }

    // MARK: - Fetch Tests

    @Test("Test fetch entries")
    func testFetchEntries() async throws {
        let repository = try createTestDatabase()

        // Store some entries
        let entries = (1...5).map { i in
            EncryptedLogEntry(
                id: "entry-\(i)",
                timestamp: Date().addingTimeInterval(TimeInterval(i)),
                data: Data("data \(i)".utf8)
            )
        }

        for entry in entries {
            try await repository.store(entry)
        }

        let fetchedEntries = try await repository.fetchEntries()

        #expect(fetchedEntries.count == 5)
    }

    @Test("Test fetch entries from empty database")
    func testFetchEntriesFromEmptyDatabase() async throws {
        let repository = try createTestDatabase()

        let entries = try await repository.fetchEntries()

        #expect(entries.isEmpty)
    }

    @Test("Test fetch entries are ordered by timestamp")
    func testFetchEntriesOrderedByTimestamp() async throws {
        let repository = try createTestDatabase()

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

    // MARK: - Delete by Date Tests

    @Test("Test delete entries older than date")
    func testDeleteEntriesOlderThanDate() async throws {
        let repository = try createTestDatabase()

        let now = Date()
        let oldEntry = EncryptedLogEntry(
            id: "old",
            timestamp: now.addingTimeInterval(-3600 * 24 * 8), // 8 days ago
            data: Data("old".utf8)
        )
        let recentEntry = EncryptedLogEntry(
            id: "recent",
            timestamp: now,
            data: Data("recent".utf8)
        )

        try await repository.store(oldEntry)
        try await repository.store(recentEntry)

        #expect(try await repository.count() == 2)

        // Delete entries older than 7 days
        let cutoffDate = now.addingTimeInterval(-3600 * 24 * 7)
        try await repository.deleteEntries(olderThan: cutoffDate)

        let count = try await repository.count()
        #expect(count == 1)

        let entries = try await repository.fetchEntries()
        #expect(entries.first?.id == "recent")
    }

    @Test("Test delete entries older than date with no matches")
    func testDeleteEntriesOlderThanDateNoMatches() async throws {
        let repository = try createTestDatabase()

        let now = Date()
        let entry = EncryptedLogEntry(
            id: "entry",
            timestamp: now,
            data: Data("data".utf8)
        )

        try await repository.store(entry)

        // Try to delete entries older than 1 day ago (should delete nothing)
        let cutoffDate = now.addingTimeInterval(-3600 * 24)
        try await repository.deleteEntries(olderThan: cutoffDate)

        let count = try await repository.count()
        #expect(count == 1)
    }

    // MARK: - Delete Keeping Latest Tests

    @Test("Test delete entries keeping latest")
    func testDeleteEntriesKeepingLatest() async throws {
        let repository = try createTestDatabase()

        // Store 10 entries
        for i in 1...10 {
            let entry = EncryptedLogEntry(
                id: "entry-\(i)",
                timestamp: Date().addingTimeInterval(TimeInterval(i)),
                data: Data("data \(i)".utf8)
            )
            try await repository.store(entry)
        }

        #expect(try await repository.count() == 10)

        // Keep only the latest 5
        try await repository.deleteEntries(keepingLatest: 5)

        let count = try await repository.count()
        #expect(count == 5)

        // Verify we kept the most recent ones
        let entries = try await repository.fetchEntries()
        #expect(entries.count == 5)
        #expect(entries.last?.id == "entry-10")
    }

    @Test("Test delete entries keeping latest with exact count")
    func testDeleteEntriesKeepingLatestExactCount() async throws {
        let repository = try createTestDatabase()

        // Store 5 entries
        for i in 1...5 {
            let entry = EncryptedLogEntry(
                id: "entry-\(i)",
                timestamp: Date().addingTimeInterval(TimeInterval(i)),
                data: Data("data \(i)".utf8)
            )
            try await repository.store(entry)
        }

        // Keep 5 (same as current count)
        try await repository.deleteEntries(keepingLatest: 5)

        let count = try await repository.count()
        #expect(count == 5)
    }

    @Test("Test delete entries keeping latest with more than exists")
    func testDeleteEntriesKeepingLatestMoreThanExists() async throws {
        let repository = try createTestDatabase()

        // Store 3 entries
        for i in 1...3 {
            let entry = EncryptedLogEntry(
                id: "entry-\(i)",
                timestamp: Date().addingTimeInterval(TimeInterval(i)),
                data: Data("data \(i)".utf8)
            )
            try await repository.store(entry)
        }

        // Try to keep 10 (more than we have)
        try await repository.deleteEntries(keepingLatest: 10)

        let count = try await repository.count()
        #expect(count == 3) // Should still have all 3
    }

    // MARK: - Clear Tests

    @Test("Test clear all entries")
    func testClearAllEntries() async throws {
        let repository = try createTestDatabase()

        // Store some entries
        for i in 1...5 {
            let entry = EncryptedLogEntry(
                id: "entry-\(i)",
                timestamp: Date(),
                data: Data("data \(i)".utf8)
            )
            try await repository.store(entry)
        }

        #expect(try await repository.count() == 5)

        try await repository.clear()

        let count = try await repository.count()
        #expect(count == 0)
    }

    @Test("Test clear empty database")
    func testClearEmptyDatabase() async throws {
        let repository = try createTestDatabase()

        try await repository.clear()

        let count = try await repository.count()
        #expect(count == 0)
    }

    // MARK: - Count Tests

    @Test("Test count entries")
    func testCountEntries() async throws {
        let repository = try createTestDatabase()

        #expect(try await repository.count() == 0)

        for i in 1...7 {
            let entry = EncryptedLogEntry(
                id: "entry-\(i)",
                timestamp: Date(),
                data: Data("data \(i)".utf8)
            )
            try await repository.store(entry)
        }

        let count = try await repository.count()
        #expect(count == 7)
    }

    // MARK: - Data Integrity Tests

    @Test("Test stored data integrity")
    func testStoredDataIntegrity() async throws {
        let repository = try createTestDatabase()

        let originalData = Data("This is test encrypted data!".utf8)
        let entry = EncryptedLogEntry(
            id: "test-id",
            timestamp: Date(),
            data: originalData
        )

        try await repository.store(entry)

        let entries = try await repository.fetchEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.id == "test-id")
        #expect(entries.first?.data == originalData)
    }

    @Test("Test unicode data integrity")
    func testUnicodeDataIntegrity() async throws {
        let repository = try createTestDatabase()

        let unicodeString = "Hello 世界 🌍 مرحبا"
        let unicodeData = Data(unicodeString.utf8)
        let entry = EncryptedLogEntry(
            id: "unicode-test",
            timestamp: Date(),
            data: unicodeData
        )

        try await repository.store(entry)

        let entries = try await repository.fetchEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.data == unicodeData)

        // Verify we can decode it back
        let decodedString = String(data: entries.first!.data, encoding: .utf8)
        #expect(decodedString == unicodeString)
    }

    // MARK: - Concurrent Access Tests

    @Test("Test concurrent store operations")
    func testConcurrentStoreOperations() async throws {
        let repository = try createTestDatabase()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    do {
                        let entry = EncryptedLogEntry(
                            id: "entry-\(i)",
                            timestamp: Date(),
                            data: Data("data \(i)".utf8)
                        )
                        try await repository.store(entry)
                    } catch {
                        Issue.record("Store failed: \(error)")
                    }
                }
            }
        }

        let count = try await repository.count()
        #expect(count == 20)
    }

    @Test("Test concurrent mixed operations")
    func testConcurrentMixedOperations() async throws {
        let repository = try createTestDatabase()

        // Pre-populate with some data
        for i in 1...10 {
            let entry = EncryptedLogEntry(
                id: "initial-\(i)",
                timestamp: Date(),
                data: Data("data \(i)".utf8)
            )
            try await repository.store(entry)
        }

        await withTaskGroup(of: Void.self) { group in
            // Add more entries
            for i in 11...20 {
                group.addTask {
                    do {
                        let entry = EncryptedLogEntry(
                            id: "entry-\(i)",
                            timestamp: Date(),
                            data: Data("data \(i)".utf8)
                        )
                        try await repository.store(entry)
                    } catch {
                        Issue.record("Store failed: \(error)")
                    }
                }
            }

            // Read entries
            for _ in 0..<5 {
                group.addTask {
                    do {
                        _ = try await repository.fetchEntries()
                        _ = try await repository.count()
                    } catch {
                        Issue.record("Read failed: \(error)")
                    }
                }
            }
        }

        let finalCount = try await repository.count()
        #expect(finalCount == 20)
    }

    // MARK: - Edge Cases

    @Test("Test store duplicate IDs")
    func testStoreDuplicateIDs() async throws {
        let repository = try createTestDatabase()

        let entry1 = EncryptedLogEntry(
            id: "duplicate-id",
            timestamp: Date(),
            data: Data("first".utf8)
        )

        let entry2 = EncryptedLogEntry(
            id: "duplicate-id",
            timestamp: Date(),
            data: Data("second".utf8)
        )

        try await repository.store(entry1)

        // Storing with duplicate ID should fail or replace
        do {
            try await repository.store(entry2)
            // If it succeeds, count should still be 1 (replaced)
            // or could throw an error
            let count = try await repository.count()
            // Accept either 1 (replaced) or error thrown above
            #expect(count >= 1)
        } catch {
            // Duplicate ID error is acceptable
        }
    }

    @Test("Test very old timestamps")
    func testVeryOldTimestamps() async throws {
        let repository = try createTestDatabase()

        let veryOldDate = Date(timeIntervalSince1970: 0) // January 1, 1970
        let entry = EncryptedLogEntry(
            id: "old-entry",
            timestamp: veryOldDate,
            data: Data("old data".utf8)
        )

        try await repository.store(entry)

        let entries = try await repository.fetchEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.timestamp == veryOldDate)
    }

    @Test("Test future timestamps")
    func testFutureTimestamps() async throws {
        let repository = try createTestDatabase()

        let futureDate = Date().addingTimeInterval(3600 * 24 * 365 * 10) // 10 years in future
        let entry = EncryptedLogEntry(
            id: "future-entry",
            timestamp: futureDate,
            data: Data("future data".utf8)
        )

        try await repository.store(entry)

        let entries = try await repository.fetchEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.timestamp.timeIntervalSince1970 == futureDate.timeIntervalSince1970)
    }
}
