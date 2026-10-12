import Collections
import Foundation
import Testing
@testable import Logr
import LogrTesting

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
        let crypto = LoggerCryptoService(store: InMemoryKeychainStore(), encryptionAlgo: .chacha)

        let original = LogEntry(level: .error, category: .network, subsystem: "t", message: "secret")
        let modern = try crypto.symmetricEncrypt(object: original)

        // Rebuild what a version before the `algorithm` field wrote: JSON with the sealed box in base64.
        let legacy = try JSONSerialization.data(withJSONObject: [
            "version": 1,
            "data": modern.dropFirst(7).base64EncodedString()
        ])

        let decrypted: LogEntry = try crypto.symmetricDecrypt(encryptedData: legacy)
        #expect(decrypted == original)
    }

    @Test("The envelope is a 7-byte header (magic, format 2, cipher, big-endian key version), then the sealed box",
          arguments: [(LoggerCryptoService.CryptoAlgo.chacha, UInt8(1)), (.aes256gcm, 2)])
    func testEnvelopeLayout(algorithm: LoggerCryptoService.CryptoAlgo, cipherByte: UInt8) throws {
        let crypto = LoggerCryptoService(store: InMemoryKeychainStore(), encryptionAlgo: algorithm)
        try crypto.rotateKey()
        try crypto.rotateKey()

        let envelope = try crypto.symmetricEncrypt(object: "payload")

        #expect(Array(envelope.prefix(7)) == [0xC5, 2, cipherByte, 0, 0, 0, 3])
        // Nonce (12 bytes), the JSON "payload" with its quotes (9 bytes), tag (16 bytes).
        #expect(envelope.count == 7 + 12 + 9 + 16)
    }

    @Test("Entries take at least 30 % less space than in Logr 1.x")
    func testEnvelopeIsSmallerThanTheLegacyOne() async throws {
        let directory = try TemporaryDirectory()
        let fixture = directory.url.appendingPathComponent("legacy.sqlite")
        try FileManager.default.copyItem(at: LegacyFixtures.url("legacy.sqlite"), to: fixture)
        let legacy = try await SQLiteStorage(databasePath: fixture.path).fetchEntries()
        let crypto = LoggerCryptoService(store: try LegacyFixtures.keychain())

        let legacySize = legacy.reduce(0) { $0 + $1.data.count }
        let currentSize = try legacy.reduce(0) { total, stored in
            let entry: LogEntry = try crypto.symmetricDecrypt(encryptedData: stored.data)
            return try total + crypto.symmetricEncrypt(object: entry).count
        }

        #expect(Double(currentSize) <= 0.7 * Double(legacySize), "\(currentSize) vs \(legacySize) bytes")
    }

    @Test("An envelope inside a larger buffer decrypts")
    func testEnvelopeSliceDecrypts() throws {
        let crypto = LoggerCryptoService(store: InMemoryKeychainStore())
        let envelope = try crypto.symmetricEncrypt(object: "sliced")
        let slice = (Data([0xFF, 0xFF]) + envelope).dropFirst(2)
        #expect(slice.startIndex == 2)

        #expect(try crypto.symmetricDecrypt(encryptedData: slice) as String == "sliced")
    }

    @Test("Malformed envelopes are rejected", arguments: [
        "truncated", "wrong magic", "unknown format", "unknown cipher", "empty"
    ])
    func testMalformedEnvelopeIsRejected(defect: String) throws {
        let crypto = LoggerCryptoService(store: InMemoryKeychainStore())
        var envelope = try crypto.symmetricEncrypt(object: "payload")
        switch defect {
        case "truncated": envelope = envelope.prefix(7)
        case "wrong magic": envelope[0] = 0xC4
        case "unknown format": envelope[1] = 3
        case "unknown cipher": envelope[2] = 9
        default: envelope = Data()
        }

        #expect(throws: LoggerCryptoError.invalidEnvelope) {
            let _: String = try crypto.symmetricDecrypt(encryptedData: envelope)
        }
    }

    @Test("A changed byte in the sealed box fails authentication")
    func testTamperedSealedBoxIsRejected() throws {
        let crypto = LoggerCryptoService(store: InMemoryKeychainStore())
        var envelope = try crypto.symmetricEncrypt(object: "payload")
        envelope[envelope.index(envelope.startIndex, offsetBy: 20)] ^= 0x01

        #expect(throws: (any Error).self) {
            let _: String = try crypto.symmetricDecrypt(encryptedData: envelope)
        }
    }

    @Test("Both AES-256-GCM and ChaCha20-Poly1305 round-trip")
    func testAlgorithmsRoundTrip() throws {
        for algo in [LoggerCryptoService.CryptoAlgo.aes256gcm, .chacha] {
            let crypto = LoggerCryptoService(store: InMemoryKeychainStore(), encryptionAlgo: algo)
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
    private func makeCrypto() -> LoggerCryptoService {
        LoggerCryptoService(store: InMemoryKeychainStore())
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
        let logr = LogR(storage: .custom(storage), cryptoService: makeCrypto())

        for index in 0 ..< 200 { logr.info("msg \(index)") }
        // Clear WITHOUT flushing first: entries may still be queued in the writer.
        try await logr.clearLogs()
        await logr.flush() // drain anything the writer still held after the clear

        #expect(logr.recentLogs.isEmpty)
        #expect(try await storage.count() == 0)
    }

    @Test("flush() returns promptly after the writer's stream has finished (R-Flush)", .timeLimit(.minutes(1)))
    func testFlushAfterShutdownDoesNotHang() async throws {
        let writer = LogWriterActor(storage: .custom(PreMRInMemoryStore()),
                                    cryptoService: makeCrypto(),
                                    configuration: .default)
        writer.ingest(LogEntry(level: .info, category: .system, subsystem: "t", message: "m"))
        writer.shutdown() // finishes the stream

        // With the `.terminated` guard, flush resumes immediately; without it the continuation
        // would be dropped and this would never return.
        await writer.flush()
    }

    @Test("logStatistics() computes correct per-level counts (R-Perf)")
    func testStatisticsComputedOffMain() async throws {
        let logr = LogR(cryptoService: makeCrypto())
        logr.info("a")
        logr.info("b")
        logr.error("c")

        let stats = await logr.logStatistics()
        #expect(stats.totalCount == 3)
        #expect(stats.countByLevel[.info] == 2)
        #expect(stats.countByLevel[.error] == 1)
    }
}
