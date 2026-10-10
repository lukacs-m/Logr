import Testing
@testable import Logr
import Foundation

/// Behaviour specific to the NDJSON file. The shared `LogRPersistence` contract is covered by
/// `StorageConformanceTests`.
@Suite("FileSystem Storage Tests")
struct FileSystemStorageTests {
    private let directory: TemporaryDirectory

    init() throws {
        directory = try TemporaryDirectory()
    }

    @Test("Test file storage creates its directory and file if needed")
    func testFileStorageCreatesFileIfNeeded() async throws {
        let nested = directory.url.appendingPathComponent("nested/logs", isDirectory: true)

        _ = try FileSystemStorage(directory: nested, fileName: "entries.json")

        #expect(FileManager.default.fileExists(atPath: nested.appendingPathComponent("entries.json").path))
    }

    @Test("The default location is Application Support/<bundle id>/Logr, excluded from backups")
    func testDefaultLocationIsExcludedFromBackup() async throws {
        let (documents, applicationSupport) = try systemDirectories()

        let storage = try FileSystemStorage(fileName: "logr_entries.ndjson", documents: documents,
                                            applicationSupport: applicationSupport)
        try await storage.store(Self.entry(1))

        let logrDirectory = Self.logrDirectory(in: applicationSupport)
        #expect(FileManager.default.fileExists(atPath: logrDirectory.appendingPathComponent("logr_entries.ndjson").path))
        #expect(try logrDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #expect(try FileManager.default.contentsOfDirectory(atPath: documents.path).isEmpty)
    }

    @Test("A file Logr 1.3 wrote to Documents moves to Application Support",
          arguments: [("logr_entries.ndjson", "logr_entries.json"), ("custom.json", "custom.json")])
    func testDocumentsFileMovesToApplicationSupport(fileName: String, legacyName: String) async throws {
        let (documents, applicationSupport) = try systemDirectories()
        try await FileSystemStorage(directory: documents, fileName: legacyName).store([Self.entry(1), Self.entry(2)])

        let storage = try FileSystemStorage(fileName: fileName, documents: documents,
                                            applicationSupport: applicationSupport)

        #expect(try await storage.fetchEntries().map(\.id) == ["e1", "e2"])
        #expect(!FileManager.default.fileExists(atPath: documents.appendingPathComponent(legacyName).path))
        #expect(FileManager.default.fileExists(
            atPath: Self.logrDirectory(in: applicationSupport).appendingPathComponent(fileName).path))
    }

    @Test("A Documents file never replaces an existing Application Support file")
    func testDocumentsFileDoesNotReplaceExistingFile() async throws {
        let (documents, applicationSupport) = try systemDirectories()
        try await FileSystemStorage(fileName: "logr_entries.ndjson", documents: documents,
                                    applicationSupport: applicationSupport).store(Self.entry(1))
        try await FileSystemStorage(directory: documents, fileName: "logr_entries.json").store(Self.entry(2))

        let storage = try FileSystemStorage(fileName: "logr_entries.ndjson", documents: documents,
                                            applicationSupport: applicationSupport)

        #expect(try await storage.fetchEntries().map(\.id) == ["e1"])
        #expect(FileManager.default.fileExists(atPath: documents.appendingPathComponent("logr_entries.json").path))
    }

    @Test("Test reading and appending to a legacy JSON-array file")
    func testReadsLegacyJSONArrayFile() async throws {
        let fileName = "entries.json"
        let fileURL = directory.url.appendingPathComponent(fileName)

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
        let storage = try FileSystemStorage(directory: directory.url, fileName: fileName)
        #expect(try await storage.count() == 3)

        // …and appending a new entry should still work, preserving the legacy ones.
        try await storage.store(EncryptedLogEntry(id: "new",
                                                  timestamp: Date().addingTimeInterval(100),
                                                  data: Data("new".utf8)))
        let entries = try await storage.fetchEntries()
        #expect(entries.count == 4)
        #expect(Set(entries.map(\.id)) == Set(["legacy-1", "legacy-2", "legacy-3", "new"]))
    }

    @Test("A torn final line is cut on open, so the next batch is never glued onto it")
    func testTornFinalLineIsTruncatedOnOpen() async throws {
        let fileName = "entries.json"
        let storage = try FileSystemStorage(directory: directory.url, fileName: fileName)
        try await storage.store((1 ... 3).map(Self.entry))
        try appendTornLine(to: fileName)

        let reopened = try FileSystemStorage(directory: directory.url, fileName: fileName)
        try await reopened.store((4 ... 6).map(Self.entry))

        #expect(try await reopened.fetchEntries().map(\.id) == ["e1", "e2", "e3", "e4", "e5", "e6"])
        #expect(try await reopened.count() == 6)
    }

    @Test("A torn line written while the file is open does not swallow the next stored entry")
    func testStoreAfterTornLineKeepsEveryNewEntry() async throws {
        let fileName = "entries.json"
        let storage = try FileSystemStorage(directory: directory.url, fileName: fileName)
        try await storage.store((1 ... 3).map(Self.entry))
        try appendTornLine(to: fileName)

        try await storage.store((4 ... 6).map(Self.entry))

        #expect(try await storage.fetchEntries().map(\.id) == ["e1", "e2", "e3", "e4", "e5", "e6"])
    }

    @Test("An undecodable legacy array is moved aside instead of being overwritten")
    func testUndecodableLegacyArrayIsMovedAside() async throws {
        let fileName = "entries.json"
        let corrupt = Data(#"[{"id":"broken","#.utf8)
        try corrupt.write(to: directory.url.appendingPathComponent(fileName))

        let storage = try FileSystemStorage(directory: directory.url, fileName: fileName)

        #expect(try await storage.fetchEntries().isEmpty)
        let asideName = try #require(try FileManager.default.contentsOfDirectory(atPath: directory.url.path)
            .first { $0.hasPrefix("\(fileName).unreadable-") })
        #expect(try Data(contentsOf: directory.url.appendingPathComponent(asideName)) == corrupt)
    }

    // Whole seconds: the file stores ISO 8601 dates, which drop fractions.
    private static func entry(_ index: Int) -> EncryptedLogEntry {
        EncryptedLogEntry(id: "e\(index)",
                          timestamp: Date(timeIntervalSince1970: 1_767_225_600 + TimeInterval(index)),
                          data: Data("d\(index)".utf8))
    }

    private func systemDirectories() throws -> (documents: URL, applicationSupport: URL) {
        let documents = directory.url.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        return (documents, directory.url.appendingPathComponent("Application Support", isDirectory: true))
    }

    private static func logrDirectory(in applicationSupport: URL) -> URL {
        applicationSupport.appendingPathComponent(Bundle.main.bundleIdentifier ?? "LogRPersistence")
            .appendingPathComponent("Logr", isDirectory: true)
    }

    /// Simulates a crash mid-append: a partial, undecodable trailing line with no newline.
    private func appendTornLine(to fileName: String) throws {
        let handle = try FileHandle(forWritingTo: directory.url.appendingPathComponent(fileName))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"id":"partial","timestamp":"#.utf8))
    }
}
