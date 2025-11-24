//
//  FileSystemStorage.swift
//  Logr
//
//  Created by martin on 02/11/2025.
//

import Foundation

public actor FileSystemStorage: LogRPersistence {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileName: String = "logr_entries.json") throws {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else {
            throw LogRErrors.directoryNotFound
        }
        fileURL = documentsPath.appendingPathComponent(fileName)

        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        try createFileIfNeededSync()
    }

    public func store(_ entry: EncryptedLogEntry) async throws {
        var entries = try await fetchEntries()
        entries.append(entry)

        entries.sort { $0.timestamp > $1.timestamp }
        try await saveEntries(entries)
    }

    public func store(_ entries: [EncryptedLogEntry]) async throws {
        var entries = try await fetchEntries()
        entries.append(contentsOf: entries)

        entries.sort { $0.timestamp > $1.timestamp }
        try await saveEntries(entries)
    }

    public func fetchEntries() async throws -> [EncryptedLogEntry] {
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([EncryptedLogEntry].self, from: data)
    }

    public func deleteEntries(olderThan date: Date) async throws {
        let entries = try await fetchEntries()
        let filteredEntries = entries.filter { $0.timestamp >= date }
        try await saveEntries(filteredEntries)
    }

    public func deleteEntries(keepingLatest count: Int) async throws {
        let entries = try await fetchEntries()
        let sortedEntries = entries.sorted { $0.timestamp > $1.timestamp }
        let entriesToKeep = Array(sortedEntries.prefix(count))
        try await saveEntries(entriesToKeep)
    }

    public func clear() async throws {
        try await saveEntries([])
    }

    public func count() async throws -> Int {
        try await fetchEntries().count
    }
}

private extension FileSystemStorage {
    nonisolated func createFileIfNeededSync() throws {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }
        let emptyEntries: [EncryptedLogEntry] = []
        let data = try encoder.encode(emptyEntries)
        try data.write(to: fileURL)
    }

    func saveEntries(_ entries: [EncryptedLogEntry]) async throws {
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }
}
