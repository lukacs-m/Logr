import Testing
@testable import Logr
import Foundation

@Suite("FileSystem Storage Tests")
struct FileSystemStorageTests {

    // MARK: - Helper to create test storage

    func createTestStorage() throws -> FileSystemStorage {
        // Use a unique filename for each test to avoid conflicts
        let uniqueFileName = "test_\(UUID().uuidString).json"
        return try FileSystemStorage(fileName: uniqueFileName)
    }

    func cleanupTestStorage(fileName: String) {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        let fileURL = documentsPath.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Initialization Tests

    @Test("Test file storage initialization")
    func testFileStorageInitialization() async throws {
        let storage = try createTestStorage()
        let count = try await storage.count()
        #expect(count == 0)
    }

    @Test("Test file storage creates file if needed")
    func testFileStorageCreatesFileIfNeeded() async throws {
        let uniqueFileName = "test_create_\(UUID().uuidString).json"
        _ = try FileSystemStorage(fileName: uniqueFileName)

        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            Issue.record("Documents directory not found")
            return
        }

        let fileURL = documentsPath.appendingPathComponent(uniqueFileName)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        // Cleanup
        cleanupTestStorage(fileName: uniqueFileName)
    }

    @Test("Test file storage initialization with existing file")
    func testFileStorageInitializationWithExistingFile() async throws {
        let uniqueFileName = "test_existing_\(UUID().uuidString).json"

        // Create first instance
        let storage1 = try FileSystemStorage(fileName: uniqueFileName)
        let entry = EncryptedLogEntry(
            id: "test-id",
            timestamp: Date(),
            data: Data("test".utf8)
        )
        try await storage1.store(entry)

        // Create second instance with same file
        let storage2 = try FileSystemStorage(fileName: uniqueFileName)
        let count = try await storage2.count()

        #expect(count == 1)

        // Cleanup
        cleanupTestStorage(fileName: uniqueFileName)
    }

    @Test("Test reading and appending to a legacy JSON-array file")
    func testReadsLegacyJSONArrayFile() async throws {
        let uniqueFileName = "test_legacy_\(UUID().uuidString).json"
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else {
            Issue.record("Documents directory not found")
            return
        }
        let fileURL = documentsPath.appendingPathComponent(uniqueFileName)

        // Write a legacy file: a single JSON array of entries (the pre-NDJSON format).
        let legacyEntries = (1 ... 3).map { index in
            EncryptedLogEntry(id: "legacy-\(index)",
                              timestamp: Date().addingTimeInterval(TimeInterval(index)),
                              data: Data("d\(index)".utf8))
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(legacyEntries).write(to: fileURL, options: .atomic)

        // Opening with FileSystemStorage should read the legacy entries…
        let storage = try FileSystemStorage(fileName: uniqueFileName)
        #expect(try await storage.count() == 3)

        // …and appending a new entry should still work, preserving the legacy ones.
        try await storage.store(EncryptedLogEntry(id: "new",
                                                  timestamp: Date().addingTimeInterval(100),
                                                  data: Data("new".utf8)))
        let entries = try await storage.fetchEntries()
        #expect(entries.count == 4)
        #expect(Set(entries.map(\.id)) == Set(["legacy-1", "legacy-2", "legacy-3", "new"]))

        cleanupTestStorage(fileName: uniqueFileName)
    }

    // MARK: - Store Tests

    @Test("Test store single entry")
    func testStoreSingleEntry() async throws {
        let storage = try createTestStorage()

        let entry = EncryptedLogEntry(
            id: UUID().uuidString,
            timestamp: Date(),
            data: Data("encrypted data".utf8)
        )

        try await storage.store(entry)

        let count = try await storage.count()
        #expect(count == 1)
    }

    @Test("Test store multiple entries")
    func testStoreMultipleEntries() async throws {
        let storage = try createTestStorage()

        for i in 1...10 {
            let entry = EncryptedLogEntry(
                id: "entry-\(i)",
                timestamp: Date(),
                data: Data("encrypted data \(i)".utf8)
            )
            try await storage.store(entry)
        }

        let count = try await storage.count()
        #expect(count == 10)
    }

    @Test("Test store entry with large data")
    func testStoreEntryWithLargeData() async throws {
        let storage = try createTestStorage()

        let largeData = Data(repeating: 0xFF, count: 100000)
        let entry = EncryptedLogEntry(
            id: UUID().uuidString,
            timestamp: Date(),
            data: largeData
        )

        try await storage.store(entry)

        let count = try await storage.count()
        #expect(count == 1)
    }

    @Test("Test store entry with empty data")
    func testStoreEntryWithEmptyData() async throws {
        let storage = try createTestStorage()

        let entry = EncryptedLogEntry(
            id: UUID().uuidString,
            timestamp: Date(),
            data: Data()
        )

        try await storage.store(entry)

        let count = try await storage.count()
        #expect(count == 1)
    }

    @Test("Test entries are returned in chronological (oldest-first) order after store")
    func testEntriesAreReturnedInChronologicalOrderAfterStore() async throws {
        let storage = try createTestStorage()

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

        try await storage.store(entry1) // older
        try await storage.store(entry2) // newer

        let entries = try await storage.fetchEntries()

        #expect(entries.count == 2)
        // Append-only storage preserves insertion order, which is chronological
        // (oldest first) — matching the LogRPersistence contract and SQLiteStorage.
        #expect(entries[0].id == "entry-1")
        #expect(entries[1].id == "entry-2")
    }

    // MARK: - Fetch Tests

    @Test("Test fetch entries")
    func testFetchEntries() async throws {
        let storage = try createTestStorage()

        // Store some entries
        let entries = (1...5).map { i in
            EncryptedLogEntry(
                id: "entry-\(i)",
                timestamp: Date().addingTimeInterval(TimeInterval(i)),
                data: Data("data \(i)".utf8)
            )
        }

        for entry in entries {
            try await storage.store(entry)
        }

        let fetchedEntries = try await storage.fetchEntries()

        #expect(fetchedEntries.count == 5)
    }

    @Test("fetchEntries(limit:) returns the latest entries, oldest-first")
    func testFetchEntriesWithLimit() async throws {
        let storage = try createTestStorage()
        let now = Date()
        for index in 1 ... 10 {
            try await storage.store(EncryptedLogEntry(id: "e\(index)",
                                                      timestamp: now.addingTimeInterval(TimeInterval(index)),
                                                      data: Data("d\(index)".utf8)))
        }

        let latest = try await storage.fetchEntries(limit: 3)
        #expect(latest.map(\.id) == ["e8", "e9", "e10"])

        let all = try await storage.fetchEntries(limit: nil)
        #expect(all.count == 10)
    }

    @Test("Test fetch entries from empty storage")
    func testFetchEntriesFromEmptyStorage() async throws {
        let storage = try createTestStorage()

        let entries = try await storage.fetchEntries()

        #expect(entries.isEmpty)
    }

    // MARK: - Delete by Date Tests

    @Test("Test delete entries older than date")
    func testDeleteEntriesOlderThanDate() async throws {
        let storage = try createTestStorage()

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

        try await storage.store(oldEntry)
        try await storage.store(recentEntry)

        #expect(try await storage.count() == 2)

        // Delete entries older than 7 days
        let cutoffDate = now.addingTimeInterval(-3600 * 24 * 7)
        try await storage.deleteEntries(olderThan: cutoffDate)

        let count = try await storage.count()
        #expect(count == 1)

        let entries = try await storage.fetchEntries()
        #expect(entries.first?.id == "recent")
    }

    @Test("Test delete entries older than date with no matches")
    func testDeleteEntriesOlderThanDateNoMatches() async throws {
        let storage = try createTestStorage()

        let now = Date()
        let entry = EncryptedLogEntry(
            id: "entry",
            timestamp: now,
            data: Data("data".utf8)
        )

        try await storage.store(entry)

        // Try to delete entries older than 1 day ago (should delete nothing)
        let cutoffDate = now.addingTimeInterval(-3600 * 24)
        try await storage.deleteEntries(olderThan: cutoffDate)

        let count = try await storage.count()
        #expect(count == 1)
    }

    @Test("Test delete all entries older than future date")
    func testDeleteAllEntriesOlderThanFutureDate() async throws {
        let storage = try createTestStorage()

        let now = Date()
        for i in 1...5 {
            let entry = EncryptedLogEntry(
                id: "entry-\(i)",
                timestamp: now.addingTimeInterval(TimeInterval(i)),
                data: Data("data \(i)".utf8)
            )
            try await storage.store(entry)
        }

        #expect(try await storage.count() == 5)

        // Delete entries older than tomorrow (should delete all)
        let futureDate = now.addingTimeInterval(3600 * 24 * 2)
        try await storage.deleteEntries(olderThan: futureDate)

        let count = try await storage.count()
        #expect(count == 0)
    }

    // MARK: - Delete Keeping Latest Tests

    @Test("Test delete entries keeping latest")
    func testDeleteEntriesKeepingLatest() async throws {
        let storage = try createTestStorage()

        // Store 10 entries with different timestamps
        let now = Date()
        for i in 1...10 {
            let entry = EncryptedLogEntry(
                id: "entry-\(i)",
                timestamp: now.addingTimeInterval(TimeInterval(i)),
                data: Data("data \(i)".utf8)
            )
            try await storage.store(entry)
        }

        #expect(try await storage.count() == 10)

        // Keep only the latest 5
        try await storage.deleteEntries(keepingLatest: 5)

        let count = try await storage.count()
        #expect(count == 5)

        // Verify we kept the most recent ones (entries 6-10), in chronological order.
        let entries = try await storage.fetchEntries()
        #expect(entries.count == 5)
        #expect(Set(entries.map(\.id)) == Set((6 ... 10).map { "entry-\($0)" }))
        #expect(entries.last?.id == "entry-10")
    }

    @Test("Test delete entries keeping latest with exact count")
    func testDeleteEntriesKeepingLatestExactCount() async throws {
        let storage = try createTestStorage()

        // Store 5 entries
        for i in 1...5 {
            let entry = EncryptedLogEntry(
                id: "entry-\(i)",
                timestamp: Date().addingTimeInterval(TimeInterval(i)),
                data: Data("data \(i)".utf8)
            )
            try await storage.store(entry)
        }

        // Keep 5 (same as current count)
        try await storage.deleteEntries(keepingLatest: 5)

        let count = try await storage.count()
        #expect(count == 5)
    }

    @Test("Test delete entries keeping latest with more than exists")
    func testDeleteEntriesKeepingLatestMoreThanExists() async throws {
        let storage = try createTestStorage()

        // Store 3 entries
        for i in 1...3 {
            let entry = EncryptedLogEntry(
                id: "entry-\(i)",
                timestamp: Date().addingTimeInterval(TimeInterval(i)),
                data: Data("data \(i)".utf8)
            )
            try await storage.store(entry)
        }

        // Try to keep 10 (more than we have)
        try await storage.deleteEntries(keepingLatest: 10)

        let count = try await storage.count()
        #expect(count == 3) // Should still have all 3
    }

    @Test("Test delete entries keeping zero")
    func testDeleteEntriesKeepingZero() async throws {
        let storage = try createTestStorage()

        // Store some entries
        for i in 1...5 {
            let entry = EncryptedLogEntry(
                id: "entry-\(i)",
                timestamp: Date(),
                data: Data("data \(i)".utf8)
            )
            try await storage.store(entry)
        }

        // Keep 0 entries (delete all)
        try await storage.deleteEntries(keepingLatest: 0)

        let count = try await storage.count()
        #expect(count == 0)
    }

    // MARK: - Clear Tests

    @Test("Test clear all entries")
    func testClearAllEntries() async throws {
        let storage = try createTestStorage()

        // Store some entries
        for i in 1...5 {
            let entry = EncryptedLogEntry(
                id: "entry-\(i)",
                timestamp: Date(),
                data: Data("data \(i)".utf8)
            )
            try await storage.store(entry)
        }

        #expect(try await storage.count() == 5)

        try await storage.clear()

        let count = try await storage.count()
        #expect(count == 0)
    }

    @Test("Test clear empty storage")
    func testClearEmptyStorage() async throws {
        let storage = try createTestStorage()

        try await storage.clear()

        let count = try await storage.count()
        #expect(count == 0)
    }

    // MARK: - Count Tests

    @Test("Test count entries")
    func testCountEntries() async throws {
        let storage = try createTestStorage()

        #expect(try await storage.count() == 0)

        for i in 1...7 {
            let entry = EncryptedLogEntry(
                id: "entry-\(i)",
                timestamp: Date(),
                data: Data("data \(i)".utf8)
            )
            try await storage.store(entry)
        }

        let count = try await storage.count()
        #expect(count == 7)
    }

    // MARK: - Data Integrity Tests

    @Test("Test stored data integrity")
    func testStoredDataIntegrity() async throws {
        let storage = try createTestStorage()

        let originalData = Data("This is test encrypted data!".utf8)
        let timestamp = Date()
        let entry = EncryptedLogEntry(
            id: "test-id",
            timestamp: timestamp,
            data: originalData
        )

        try await storage.store(entry)

        let entries = try await storage.fetchEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.id == "test-id")
        #expect(entries.first?.data == originalData)
        // Allow small timestamp difference due to encoding/decoding
        #expect(abs(entries.first!.timestamp.timeIntervalSince1970 - timestamp.timeIntervalSince1970) < 1.0)
    }

    @Test("Test unicode data integrity")
    func testUnicodeDataIntegrity() async throws {
        let storage = try createTestStorage()

        let unicodeString = "Hello 世界 🌍 مرحبا"
        let unicodeData = Data(unicodeString.utf8)
        let entry = EncryptedLogEntry(
            id: "unicode-test",
            timestamp: Date(),
            data: unicodeData
        )

        try await storage.store(entry)

        let entries = try await storage.fetchEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.data == unicodeData)

        // Verify we can decode it back
        let decodedString = String(data: entries.first!.data, encoding: .utf8)
        #expect(decodedString == unicodeString)
    }

    @Test("Test multiple stores maintain data integrity")
    func testMultipleStoresMaintainDataIntegrity() async throws {
        let storage = try createTestStorage()

        let testData = [
            ("id1", "Data one"),
            ("id2", "Data two"),
            ("id3", "Data three")
        ]

        for (id, message) in testData {
            let entry = EncryptedLogEntry(
                id: id,
                timestamp: Date(),
                data: Data(message.utf8)
            )
            try await storage.store(entry)
        }

        let entries = try await storage.fetchEntries()
        #expect(entries.count == 3)

        // Verify all data is intact
        for (id, message) in testData {
            let foundEntry = entries.first { $0.id == id }
            #expect(foundEntry != nil)
            let decodedMessage = String(data: foundEntry!.data, encoding: .utf8)
            #expect(decodedMessage == message)
        }
    }

    // MARK: - Concurrent Access Tests

    @Test("Test concurrent store operations")
    func testConcurrentStoreOperations() async throws {
        let storage = try createTestStorage()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    do {
                        let entry = EncryptedLogEntry(
                            id: "entry-\(i)",
                            timestamp: Date().addingTimeInterval(TimeInterval(i)),
                            data: Data("data \(i)".utf8)
                        )
                        try await storage.store(entry)
                    } catch {
                        Issue.record("Store failed: \(error)")
                    }
                }
            }
        }
        
        let count = try await storage.count()
        #expect(count == 20)
    }

    @Test("Test concurrent mixed operations")
    func testConcurrentMixedOperations() async throws {
        let storage = try createTestStorage()

        // Pre-populate with some data
        for i in 1...10 {
            let entry = EncryptedLogEntry(
                id: "initial-\(i)",
                timestamp: Date().addingTimeInterval(TimeInterval(i)),
                data: Data("data \(i)".utf8)
            )
            try await storage.store(entry)
        }

        await withTaskGroup(of: Void.self) { group in
            // Add more entries
            for i in 11...20 {
                group.addTask {
                    do {
                        let entry = EncryptedLogEntry(
                            id: "entry-\(i)",
                            timestamp: Date().addingTimeInterval(TimeInterval(i)),
                            data: Data("data \(i)".utf8)
                        )
                        try await storage.store(entry)
                    } catch {
                        Issue.record("Store failed: \(error)")
                    }
                }
            }

            // Read entries
            for _ in 0..<5 {
                group.addTask {
                    do {
                        _ = try await storage.fetchEntries()
                        _ = try await storage.count()
                    } catch {
                        Issue.record("Read failed: \(error)")
                    }
                }
            }
        }
        
        let finalCount = try await storage.count()
        #expect(finalCount == 20)
    }

    // MARK: - Edge Cases

    @Test("Test very old timestamps")
    func testVeryOldTimestamps() async throws {
        let storage = try createTestStorage()

        let veryOldDate = Date(timeIntervalSince1970: 0) // January 1, 1970
        let entry = EncryptedLogEntry(
            id: "old-entry",
            timestamp: veryOldDate,
            data: Data("old data".utf8)
        )

        try await storage.store(entry)

        let entries = try await storage.fetchEntries()
        #expect(entries.count == 1)
        #expect(abs(entries.first!.timestamp.timeIntervalSince1970 - veryOldDate.timeIntervalSince1970) < 1.0)
    }

    @Test("Test future timestamps")
    func testFutureTimestamps() async throws {
        let storage = try createTestStorage()

        let futureDate = Date().addingTimeInterval(3600 * 24 * 365 * 10) // 10 years in future
        let entry = EncryptedLogEntry(
            id: "future-entry",
            timestamp: futureDate,
            data: Data("future data".utf8)
        )

        try await storage.store(entry)

        let entries = try await storage.fetchEntries()
        #expect(entries.count == 1)
        #expect(abs(entries.first!.timestamp.timeIntervalSince1970 - futureDate.timeIntervalSince1970) < 1.0)
    }

    @Test("Test store with special characters in data")
    func testStoreWithSpecialCharactersInData() async throws {
        let storage = try createTestStorage()

        let specialData = "Special: \n\t\"quotes\" and \\backslash\\ and emoji 🎉"
        let entry = EncryptedLogEntry(
            id: "special",
            timestamp: Date(),
            data: Data(specialData.utf8)
        )

        try await storage.store(entry)

        let entries = try await storage.fetchEntries()
        #expect(entries.count == 1)

        let retrievedData = String(data: entries.first!.data, encoding: .utf8)
        #expect(retrievedData == specialData)
    }

    @Test("Test persistence across storage instances")
    func testPersistenceAcrossStorageInstances() async throws {
        let uniqueFileName = "test_persistence_\(UUID().uuidString).json"

        // First instance - store data
        let storage1 = try FileSystemStorage(fileName: uniqueFileName)
        let entry = EncryptedLogEntry(
            id: "test-id",
            timestamp: Date(),
            data: Data("persistent data".utf8)
        )
        try await storage1.store(entry)

        // Second instance - read data
        let storage2 = try FileSystemStorage(fileName: uniqueFileName)
        let count = try await storage2.count()
        #expect(count == 1)

        let entries = try await storage2.fetchEntries()
        #expect(entries.first?.id == "test-id")

        // Cleanup
        cleanupTestStorage(fileName: uniqueFileName)
    }

    @Test("Test file is atomic write")
    func testFileIsAtomicWrite() async throws {
        let storage = try createTestStorage()

        // Store initial data
        for i in 1...5 {
            let entry = EncryptedLogEntry(
                id: "entry-\(i)",
                timestamp: Date(),
                data: Data("data \(i)".utf8)
            )
            try await storage.store(entry)
        }

        // Clear should be atomic - either all data is there or none
        try await storage.clear()
        let count = try await storage.count()
        #expect(count == 0)
    }

    @Test("Test large number of entries")
    func testLargeNumberOfEntries() async throws {
        let storage = try createTestStorage()

        // Store 100 entries
        for i in 1...100 {
            let entry = EncryptedLogEntry(
                id: "entry-\(i)",
                timestamp: Date().addingTimeInterval(TimeInterval(i)),
                data: Data("data \(i)".utf8)
            )
            try await storage.store(entry)
        }

        let count = try await storage.count()
        #expect(count == 100)

        // Verify we can fetch all
        let entries = try await storage.fetchEntries()
        #expect(entries.count == 100)
    }
}
