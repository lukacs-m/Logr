import Collections
import Foundation
import Testing
@testable import Logr
import LogrTesting

// Tests await events, not the clock; the limit turns a missed event into a failure instead of a hang.
@Suite("Reliability regressions", .timeLimit(.minutes(1)))
struct ReliabilityRegressionTests {
    @Test func partialBatchPersistsWithoutExplicitFlush() async throws {
        let storage = FlakyStorage(failingFirst: 0)
        var persisted = storage.stores.makeAsyncIterator()
        let writer = LogWriterActor(storage: storage,
                                    cryptoService: try LoggerCryptoService(store: InMemoryKeychainStore()),
                                    configuration: .default,
                                    partialBatchDeadline: .milliseconds(10))
        defer { writer.shutdown() }
        let entry = LogEntry(level: .error, category: .system, subsystem: "test", message: "last error")
        writer.ingest(entry)

        let batch = await persisted.next()

        #expect(batch?.map(\.id) == [entry.id])
    }

    @Test func startupMergeKeepsUniqueEntries() {
        let entry = LogEntry(level: .info, category: .system, subsystem: "test", message: "during startup")
        var current: Deque<LogEntry> = [entry]
        LogR.mergeLoaded([entry], into: &current, cap: 100)
        #expect(current.count == 1)
        #expect(Set(current.map(\.id)).count == current.count)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, *)
    @Test func startupFetchOverlappingLiveWritesDoesNotDuplicateThem() async throws {
        let crypto = try LoggerCryptoService(store: InMemoryKeychainStore())
        let historical = LogEntry(level: .info, category: .system, subsystem: "test", message: "history")
        let encrypted = EncryptedLogEntry(id: historical.id, timestamp: historical.timestamp,
                                          data: try crypto.symmetricEncrypt(object: historical))
        let storage = StartupOverlapStorage(history: encrypted)
        let logger = LogR(storage: storage, cryptoService: crypto,
                          configuration: LogrConfiguration(mirrorToOSLog: false))
        logger.info("live")
        await logger.flush()
        await storage.releaseFetch()
        _ = await Observations { logger.recentLogs }.first { $0.contains { $0.id == historical.id } }
        #expect(logger.recentLogs.map(\.message) == ["live", "history"])
        #expect(Set(logger.recentLogs.map(\.id)).count == logger.recentLogs.count)
    }

    @Test func shutdownDrainsPartialBatchAndReleasesWriter() async throws {
        var storage: FlakyStorage? = FlakyStorage(failingFirst: 0)
        let stores = storage!.stores
        var writer: LogWriterActor? = LogWriterActor(storage: storage!,
            cryptoService: try LoggerCryptoService(store: InMemoryKeychainStore()), configuration: .default)
        storage = nil
        writer?.ingest(LogEntry(level: .info, category: .system, subsystem: "test", message: "shutdown"))
        writer?.shutdown()
        writer = nil

        // The writer owns the storage now, so `stores` only finishes once the writer is released.
        var persisted = 0
        for await batch in stores {
            persisted += batch.count
        }
        #expect(persisted == 1)
    }

    @Test func timedFlushAfterClearOnlyPersistsNewEntries() async throws {
        let storage = FlakyStorage(failingFirst: 0)
        let writer = LogWriterActor(storage: storage,
                                    cryptoService: try LoggerCryptoService(store: InMemoryKeychainStore()),
                                    configuration: .default,
                                    partialBatchDeadline: .milliseconds(10))
        defer { writer.shutdown() }
        writer.ingest(LogEntry(level: .error, category: .system, subsystem: "test", message: "cleared"))
        try await writer.clearPending()
        let survivor = LogEntry(level: .info, category: .system, subsystem: "test", message: "survivor")
        writer.ingest(survivor)
        _ = await storage.stores.first { $0.contains { $0.id == survivor.id } }
        #expect(await storage.entries.map(\.id) == [survivor.id])
        await writer.flush()
        #expect(await storage.entries.map(\.id) == [survivor.id])
    }

    @Test func partialBatchRetriesOnDeadline() async throws {
        let storage = FlakyStorage(failingFirst: 1)
        var persisted = storage.stores.makeAsyncIterator()
        let writer = LogWriterActor(storage: storage,
                                    cryptoService: try LoggerCryptoService(store: InMemoryKeychainStore()),
                                    configuration: .default,
                                    partialBatchDeadline: .milliseconds(10))
        defer { writer.shutdown() }
        let entry = LogEntry(level: .error, category: .system, subsystem: "test", message: "retry")
        writer.ingest(entry)

        let batch = await persisted.next()

        #expect(batch?.map(\.id) == [entry.id])
    }

    @Test(arguments: [LoggerCryptoService.CryptoAlgo.aes256gcm, .chacha])
    func rotationDuringEncodingPreservesDecryptability(algorithm: LoggerCryptoService.CryptoAlgo) throws {
        let crypto = try LoggerCryptoService(store: InMemoryKeychainStore(), encryptionAlgo: algorithm)
        let data = try crypto.symmetricEncrypt(object: RotatingPayload(crypto: crypto))
        let decoded: String = try crypto.symmetricDecrypt(encryptedData: data)
        #expect(decoded == "payload")
    }

    @Test func concurrentRotationsKeepDistinctVersions() async throws {
        let crypto = try LoggerCryptoService(store: InMemoryKeychainStore())
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
