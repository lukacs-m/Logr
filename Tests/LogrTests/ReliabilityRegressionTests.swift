import Collections
import Foundation
import Testing
import os
@testable import Logr

final class LockedKeychainStore: KeychainStore {
    private let values = OSAllocatedUnfairLock(initialState: [String: Data]())

    func data(forKey key: String) throws -> Data? { values.withLock { $0[key] } }
    func set(_ data: Data, forKey key: String) throws { values.withLock { $0[key] = data } }
    func remove(forKey key: String) throws { values.withLock { $0[key] = nil } }
}

@Suite("Reliability regressions")
struct ReliabilityRegressionTests {
    @Test func partialBatchPersistsWithoutExplicitFlush() async throws {
        let storage = FlakyStorage(failingFirst: 0)
        let writer = LogWriterActor(storage: storage,
                                    cryptoService: try LoggerCryptoService(store: LockedKeychainStore()),
                                    configuration: .default)
        defer { writer.shutdown() }
        writer.ingest(LogEntry(level: .error, category: .system, subsystem: "test", message: "last error"))
        for _ in 0..<100 {
            if await storage.storedCount == 1 { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(await storage.storedCount == 1)
    }

    @Test func startupMergeKeepsUniqueEntries() {
        let entry = LogEntry(level: .info, category: .system, subsystem: "test", message: "during startup")
        var current: Deque<LogEntry> = [entry]
        LogR.mergeLoaded([entry], into: &current, cap: 100)
        #expect(current.count == 1)
        #expect(Set(current.map(\.id)).count == current.count)
    }

    @Test func startupFetchOverlappingLiveWritesDoesNotDuplicateThem() async throws {
        let crypto = try LoggerCryptoService(store: LockedKeychainStore())
        let historical = LogEntry(level: .info, category: .system, subsystem: "test", message: "history")
        let encrypted = EncryptedLogEntry(id: historical.id, timestamp: historical.timestamp,
                                          data: try crypto.symmetricEncrypt(object: historical))
        let storage = StartupOverlapStorage(history: encrypted)
        let logger = LogR(storage: storage, cryptoService: crypto,
                          configuration: LogrConfiguration(mirrorToOSLog: false))
        logger.info("live")
        await logger.flush()
        await storage.releaseFetch()
        for _ in 0..<100 {
            if logger.recentLogs.contains(where: { $0.id == historical.id }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(logger.recentLogs.map(\.message) == ["live", "history"])
        #expect(Set(logger.recentLogs.map(\.id)).count == logger.recentLogs.count)
    }

    @Test func shutdownDrainsPartialBatchAndReleasesWriter() async throws {
        let storage = FlakyStorage(failingFirst: 0)
        var writer: LogWriterActor? = LogWriterActor(storage: storage,
            cryptoService: try LoggerCryptoService(store: LockedKeychainStore()), configuration: .default)
        weak var releasedWriter = writer
        writer?.ingest(LogEntry(level: .info, category: .system, subsystem: "test", message: "shutdown"))
        writer?.shutdown()
        writer = nil
        for _ in 0..<100 {
            if releasedWriter == nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(releasedWriter == nil)
        #expect(await storage.storedCount == 1)
    }

    @Test func timedFlushAfterClearOnlyPersistsNewEntries() async throws {
        let storage = FlakyStorage(failingFirst: 0)
        let writer = LogWriterActor(storage: storage,
                                    cryptoService: try LoggerCryptoService(store: LockedKeychainStore()),
                                    configuration: .default)
        defer { writer.shutdown() }
        writer.ingest(LogEntry(level: .error, category: .system, subsystem: "test", message: "cleared"))
        try await writer.clearPending()
        let survivor = LogEntry(level: .info, category: .system, subsystem: "test", message: "survivor")
        writer.ingest(survivor)
        for _ in 0..<100 {
            if await storage.storedCount == 1 { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(await storage.entries.map(\.id) == [survivor.id])
        await writer.flush()
        #expect(await storage.entries.map(\.id) == [survivor.id])
    }

    @Test func partialBatchRetriesOnDeadline() async throws {
        let storage = FlakyStorage(failingFirst: 1)
        let writer = LogWriterActor(storage: storage,
                                    cryptoService: try LoggerCryptoService(store: LockedKeychainStore()),
                                    configuration: .default)
        defer { writer.shutdown() }
        writer.ingest(LogEntry(level: .error, category: .system, subsystem: "test", message: "retry"))
        for _ in 0..<100 {
            if await storage.storedCount == 1 { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(await storage.storedCount == 1)
    }

    @Test(arguments: [LoggerCryptoService.CryptoAlgo.aes256gcm, .chacha])
    func rotationDuringEncodingPreservesDecryptability(algorithm: LoggerCryptoService.CryptoAlgo) throws {
        let crypto = try LoggerCryptoService(store: LockedKeychainStore(), encryptionAlgo: algorithm)
        let data = try crypto.symmetricEncrypt(object: RotatingPayload(crypto: crypto))
        let decoded: String = try crypto.symmetricDecrypt(encryptedData: data)
        #expect(decoded == "payload")
    }

    @Test func concurrentRotationsKeepDistinctVersions() async throws {
        let crypto = try LoggerCryptoService(store: LockedKeychainStore())
        let original = try crypto.symmetricEncrypt(object: "before rotation")
        try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0..<30 {
                group.addTask {
                    try crypto.rotateKey()
                    return try crypto.symmetricEncrypt(object: "after rotation")
                }
            }
            for try await data in group {
                let decoded: String = try crypto.symmetricDecrypt(encryptedData: data)
                #expect(decoded == "after rotation")
            }
        }
        #expect(crypto.currentKeyVersion.value.value == 31)
        let decoded: String = try crypto.symmetricDecrypt(encryptedData: original)
        #expect(decoded == "before rotation")
    }

    private struct RotatingPayload: Codable, Sendable {
        let crypto: LoggerCryptoService
        init(crypto: LoggerCryptoService) { self.crypto = crypto }
        init(from decoder: any Decoder) throws { throw CocoaError(.coderReadCorrupt) }
        func encode(to encoder: any Encoder) throws {
            // Force the interleaving between key selection and envelope construction.
            try crypto.rotateKey()
            var container = encoder.singleValueContainer()
            try container.encode("payload")
        }
    }
}

private actor StartupOverlapStorage: LogRPersistence {
    private var entries: [EncryptedLogEntry]
    private var fetchReleased = false
    private var fetchWaiter: CheckedContinuation<Void, Never>?

    init(history: EncryptedLogEntry) { entries = [history] }
    func store(_ entry: EncryptedLogEntry) async throws { entries.append(entry) }
    func fetchEntries() async throws -> [EncryptedLogEntry] {
        if !fetchReleased {
            await withCheckedContinuation { fetchWaiter = $0 }
        }
        return entries
    }
    func releaseFetch() {
        fetchReleased = true
        fetchWaiter?.resume()
        fetchWaiter = nil
    }
    func count() async throws -> Int { entries.count }
    func clear() async throws { entries.removeAll() }
    func deleteEntries(olderThan date: Date) async throws { entries.removeAll { $0.timestamp < date } }
    func deleteEntries(keepingLatest count: Int) async throws { entries = Array(entries.suffix(count)) }
}
