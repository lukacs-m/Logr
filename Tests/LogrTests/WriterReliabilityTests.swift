import Testing
@testable import Logr
import Foundation

/// In-memory storage whose batch `store` throws for the first `failingFirst` calls,
/// then succeeds. Used to prove the background writer re-tries a failed batch instead
/// of silently dropping it.
actor FlakyStorage: LogRPersistence {
    enum StorageError: Error { case transient }

    private var failuresRemaining: Int
    private(set) var entries: [EncryptedLogEntry] = []

    init(failingFirst failures: Int) {
        failuresRemaining = failures
    }

    var storedCount: Int { entries.count }

    func store(_ entry: EncryptedLogEntry) async throws {
        try await store([entry])
    }

    func store(_ newEntries: [EncryptedLogEntry]) async throws {
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw StorageError.transient
        }
        entries.append(contentsOf: newEntries)
    }

    func fetchEntries() async throws -> [EncryptedLogEntry] { entries }

    func deleteEntries(olderThan date: Date) async throws {
        entries.removeAll { $0.timestamp < date }
    }

    func deleteEntries(keepingLatest count: Int) async throws {
        entries = Array(entries.suffix(count))
    }

    func clear() async throws { entries.removeAll() }

    func count() async throws -> Int { entries.count }
}

@MainActor
@Suite("Writer Reliability")
struct WriterReliabilityTests {
    private func makeCrypto() throws -> LoggerCryptoService {
        try LoggerCryptoService(store: MockKeychainService())
    }

    @Test("A transient store failure does not lose log entries")
    func testTransientFailureDoesNotDrop() async throws {
        let storage = FlakyStorage(failingFirst: 1)
        let logr = LogR(storage: storage, cryptoService: try makeCrypto())

        logr.info("a")
        logr.info("b")
        logr.info("c")

        await logr.flush()

        let stored = await storage.storedCount
        #expect(stored == 3)
    }

    @Test("All logged entries are persisted after flush")
    func testFlushPersistsAll() async throws {
        let storage = FlakyStorage(failingFirst: 0)
        let logr = LogR(storage: storage, cryptoService: try makeCrypto())

        for index in 0 ..< 120 {
            logr.info("msg \(index)")
        }
        await logr.flush()

        let stored = await storage.storedCount
        #expect(stored == 120)
    }
}
