import Foundation
import Testing
@testable import Logr

/// The built-in `LogRPersistence` backends, each opened at a fixed location inside `directory`.
enum StorageBackend: CaseIterable {
    case fileSystem
    case sqlite

    func open(in directory: URL) throws -> any LogRPersistence {
        switch self {
        case .fileSystem:
            try FileSystemStorage(directory: directory, fileName: "logs.ndjson")
        case .sqlite:
            try SQLiteStorage(databasePath: directory.appendingPathComponent("logs.sqlite").path)
        }
    }
}

@Suite("LogRPersistence conformance")
struct StorageConformanceTests {
    private let directory: TemporaryDirectory

    init() throws {
        directory = try TemporaryDirectory()
    }

    // Whole seconds: FileSystemStorage writes ISO 8601 dates, which drop fractions.
    private static let start = Date(timeIntervalSince1970: 1_767_225_600)

    private static func entry(_ index: Int, data: Data? = nil) -> EncryptedLogEntry {
        EncryptedLogEntry(id: "e\(index)",
                          timestamp: start.addingTimeInterval(TimeInterval(index)),
                          data: data ?? Data("d\(index)".utf8))
    }

    @Test(arguments: StorageBackend.allCases)
    func fetchEntriesReturnsOldestFirst(backend: StorageBackend) async throws {
        let storage = try backend.open(in: directory.url)
        #expect(try await storage.fetchEntries().isEmpty)

        try await storage.store(Self.entry(1))
        try await storage.store((2 ... 5).map { Self.entry($0) })

        #expect(try await storage.fetchEntries().map(\.id) == ["e1", "e2", "e3", "e4", "e5"])
    }

    @Test(arguments: StorageBackend.allCases)
    func fetchEntriesWithLimitReturnsTheLatestOldestFirst(backend: StorageBackend) async throws {
        let storage = try backend.open(in: directory.url)
        try await storage.store((1 ... 10).map { Self.entry($0) })

        #expect(try await storage.fetchEntries(limit: 3).map(\.id) == ["e8", "e9", "e10"])
        #expect(try await storage.fetchEntries(limit: 20).count == 10)
        #expect(try await storage.fetchEntries(limit: nil).count == 10)
    }

    @Test(arguments: StorageBackend.allCases)
    func deleteOlderThanKeepsTheEntryAtTheCutoff(backend: StorageBackend) async throws {
        let storage = try backend.open(in: directory.url)
        try await storage.store((1 ... 5).map { Self.entry($0) })

        try await storage.deleteEntries(olderThan: Self.entry(3).timestamp)

        #expect(try await storage.fetchEntries().map(\.id) == ["e3", "e4", "e5"])
    }

    @Test(arguments: StorageBackend.allCases, [0, 3, 5, 10])
    func deleteKeepingLatestKeepsTheNewest(backend: StorageBackend, keep: Int) async throws {
        let storage = try backend.open(in: directory.url)
        try await storage.store((1 ... 5).map { Self.entry($0) })

        try await storage.deleteEntries(keepingLatest: keep)

        let expected = (1 ... 5).suffix(keep).map { "e\($0)" }
        #expect(try await storage.fetchEntries().map(\.id) == expected)
    }

    @Test(arguments: StorageBackend.allCases)
    func clearRemovesEverythingAndStorageStaysUsable(backend: StorageBackend) async throws {
        let storage = try backend.open(in: directory.url)
        try await storage.store((1 ... 5).map { Self.entry($0) })

        try await storage.clear()
        #expect(try await storage.count() == 0)
        #expect(try await storage.fetchEntries().isEmpty)

        try await storage.store(Self.entry(6))
        #expect(try await storage.fetchEntries().map(\.id) == ["e6"])
    }

    @Test(arguments: StorageBackend.allCases)
    func countMatchesFetchedEntries(backend: StorageBackend) async throws {
        let storage = try backend.open(in: directory.url)
        #expect(try await storage.count() == 0)

        // Raw newlines in the payload must not inflate FileSystemStorage's line-based count.
        try await storage.store((1 ... 100).map { Self.entry($0, data: Data("multi\nline \($0)".utf8)) })

        #expect(try await storage.count() == 100)
        #expect(try await storage.fetchEntries().count == 100)
    }

    @Test(arguments: StorageBackend.allCases)
    func duplicateIDLeavesTheStoredEntryIntact(backend: StorageBackend) async throws {
        let storage = try backend.open(in: directory.url)
        let original = Self.entry(1)
        try await storage.store(original)

        // SQLiteStorage ignores the duplicate and FileSystemStorage keeps both; either way the
        // original must survive and `count()` must agree with what `fetchEntries()` returns.
        _ = try? await storage.store(Self.entry(1, data: Data("duplicate".utf8)))

        let entries = try await storage.fetchEntries()
        #expect(entries.first == original)
        #expect(try await storage.count() == entries.count)
    }

    @Test(arguments: StorageBackend.allCases)
    func entriesWithTheSameTimestampKeepTheirWriteOrder(backend: StorageBackend) async throws {
        let storage = try backend.open(in: directory.url)
        let ids = ["c", "a", "d", "b", "e"]
        let entries = ids.map { EncryptedLogEntry(id: $0, timestamp: Self.start, data: Data($0.utf8)) }
        try await storage.store(entries[0])
        try await storage.store(Array(entries[1...]))

        #expect(try await storage.fetchEntries().map(\.id) == ids)
        #expect(try await storage.fetchEntries(limit: 2).map(\.id) == ["b", "e"])

        try await storage.deleteEntries(keepingLatest: 3)
        #expect(try await storage.fetchEntries().map(\.id) == ["d", "b", "e"])
    }

    @Test(arguments: StorageBackend.allCases)
    func reopeningReturnsEveryEntryUnchanged(backend: StorageBackend) async throws {
        let entries = [
            EncryptedLogEntry(id: "epoch", timestamp: Date(timeIntervalSince1970: 0), data: Data()),
            Self.entry(1, data: Data(repeating: 0xFF, count: 100_000)),
            Self.entry(2, data: Data("Hello 世界 🌍 مرحبا".utf8)),
            Self.entry(3, data: Data("Special: \n\t\"quotes\" and \\backslash\\".utf8)),
            EncryptedLogEntry(id: "future", timestamp: Self.start.addingTimeInterval(10 * 365 * 24 * 3600),
                              data: Data("future".utf8))
        ]
        try await backend.open(in: directory.url).store(entries)

        let reopened = try backend.open(in: directory.url)

        #expect(try await reopened.fetchEntries() == entries)
    }

    @Test(arguments: StorageBackend.allCases)
    func concurrentStoresAreAllPersisted(backend: StorageBackend) async throws {
        let storage = try backend.open(in: directory.url)

        try await withThrowingTaskGroup { group in
            for index in 1 ... 20 {
                group.addTask { try await storage.store(Self.entry(index)) }
            }
            for _ in 1 ... 5 {
                group.addTask { _ = try await (storage.fetchEntries(), storage.count()) }
            }
            try await group.waitForAll()
        }

        #expect(try await storage.count() == 20)
        #expect(Set(try await storage.fetchEntries().map(\.id)) == Set((1 ... 20).map { "e\($0)" }))
    }
}
