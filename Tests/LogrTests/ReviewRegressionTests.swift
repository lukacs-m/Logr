import Collections
import Foundation
import Testing
@testable import Logr

// MARK: - Shared test storage

/// In-memory storage implementing **only** the pre-MR `LogRPersistence` primitives — no
/// `store(_ entries:)` and no `fetchEntries(limit:)`. Its mere existence proves the new batch
/// requirement ships a working default (C2); it also doubles as functional storage for the
/// clear-resurrection test (C3).
actor PreMRInMemoryStore: LogRPersistence {
    private(set) var entries: [EncryptedLogEntry] = []

    func store(_ entry: EncryptedLogEntry) async throws { entries.append(entry) }
    func fetchEntries() async throws -> [EncryptedLogEntry] { entries }
    func deleteEntries(olderThan date: Date) async throws { entries.removeAll { $0.timestamp <= date } }
    func deleteEntries(keepingLatest count: Int) async throws { entries = Array(entries.suffix(count)) }
    func clear() async throws { entries.removeAll() }
    func count() async throws -> Int { entries.count }
}

// MARK: - C1: crypto envelope backward/forward compatibility

@Suite("Crypto envelope back-compat (C1)")
struct CryptoEnvelopeBackCompatTests {
    @Test("Legacy envelope without an `algorithm` field decrypts as ChaCha20-Poly1305")
    func testLegacyEnvelopeDecodesAsChaCha() throws {
        let crypto = try LoggerCryptoService(store: MockKeychainService(), encryptionAlgo: .chacha)

        let original = LogEntry(level: .error, category: .network, subsystem: "t", message: "secret")
        let modern = try crypto.symmetricEncrypt(object: original)

        // Reproduce an envelope written by a version that predates the `algorithm` field.
        var json = try #require(try JSONSerialization.jsonObject(with: modern) as? [String: Any])
        #expect(json["algorithm"] != nil) // sanity: current encoder writes it
        json.removeValue(forKey: "algorithm")
        let legacy = try JSONSerialization.data(withJSONObject: json)

        let decrypted: LogEntry = try crypto.symmetricDecrypt(encryptedData: legacy)
        #expect(decrypted == original)
    }

    @Test("Both AES-256-GCM and ChaCha20-Poly1305 round-trip")
    func testAlgorithmsRoundTrip() throws {
        for algo in [LoggerCryptoService.CryptoAlgo.aes256gcm, .chacha] {
            let crypto = try LoggerCryptoService(store: MockKeychainService(), encryptionAlgo: algo)
            let original = LogEntry(level: .info, category: .system, subsystem: "t", message: "hello")
            let data = try crypto.symmetricEncrypt(object: original)
            let decrypted: LogEntry = try crypto.symmetricDecrypt(encryptedData: data)
            #expect(decrypted == original)
        }
    }
}

// MARK: - C2 / C3 / R-Flush

@MainActor
@Suite("Review regressions (C2, C3, R-Flush)")
struct ReviewRegressionTests {
    private func makeCrypto() throws -> LoggerCryptoService {
        try LoggerCryptoService(store: MockKeychainService())
    }

    @Test("A custom backend implementing only pre-MR methods batches via the default (C2)")
    func testBatchStoreDefaultForCustomBackend() async throws {
        let store = PreMRInMemoryStore()
        let entries = (0 ..< 3).map {
            EncryptedLogEntry(id: "\($0)", timestamp: Date(), data: Data([UInt8($0)]))
        }
        // Resolves to the `LogRPersistence` extension default — the type compiles without its own
        // `store(_ entries:)`, which is the compatibility guarantee.
        try await store.store(entries)
        #expect(try await store.count() == 3)
    }

    @Test("clearLogs() clears storage even with writes still buffered — no resurrection (C3)")
    func testClearLogsLeavesNoResurrectedEntries() async throws {
        let storage = PreMRInMemoryStore()
        let logr = LogR(storage: storage, cryptoService: try makeCrypto())

        for index in 0 ..< 200 { logr.info("msg \(index)") }
        // Clear WITHOUT flushing first: entries may still be queued in the writer.
        try await logr.clearLogs()
        await logr.flush() // drain anything the writer still held after the clear

        #expect(logr.recentLogs.isEmpty)
        #expect(try await storage.count() == 0)
    }

    @Test("flush() returns promptly after the writer's stream has finished (R-Flush)")
    func testFlushAfterShutdownDoesNotHang() async throws {
        let writer = LogWriterActor(storage: PreMRInMemoryStore(),
                                    cryptoService: try makeCrypto(),
                                    configuration: .default)
        writer.ingest(LogEntry(level: .info, category: .system, subsystem: "t", message: "m"))
        writer.shutdown() // finishes the stream

        // Race flush() against a timeout. With the `.terminated` guard, flush resumes immediately;
        // without it the continuation would be dropped and this would never return.
        let returned = await withTaskGroup(of: Bool.self) { group in
            group.addTask { await writer.flush(); return true }
            group.addTask { try? await Task.sleep(for: .seconds(2)); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        #expect(returned)
    }

    @Test("logStatistics() computes correct per-level counts (R-Perf)")
    func testStatisticsComputedOffMain() async throws {
        let logr = LogR(cryptoService: try makeCrypto())
        logr.info("a")
        logr.info("b")
        logr.error("c")

        let stats = await logr.logStatistics()
        #expect(stats.totalCount == 3)
        #expect(stats.countByLevel[.info] == 2)
        #expect(stats.countByLevel[.error] == 1)
    }
}
