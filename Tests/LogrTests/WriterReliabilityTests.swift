import Testing
@testable import Logr
import Foundation
import os

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

/// In-memory storage that delays every write, so entries pile up in the writer's pending buffer
/// faster than they drain. Used to exercise backpressure.
actor SlowStorage: LogRPersistence {
    private let delay: Duration
    private(set) var entries: [EncryptedLogEntry] = []

    init(delay: Duration) { self.delay = delay }

    var storedCount: Int { entries.count }

    func store(_ entry: EncryptedLogEntry) async throws { try await store([entry]) }

    func store(_ newEntries: [EncryptedLogEntry]) async throws {
        try? await Task.sleep(for: delay)
        entries.append(contentsOf: newEntries)
    }

    func fetchEntries() async throws -> [EncryptedLogEntry] { entries }
    func deleteEntries(olderThan date: Date) async throws {}
    func deleteEntries(keepingLatest count: Int) async throws {}
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

    @Test("droppedLogCount surfaces persistence loss through the LogRService existential")
    func testDroppedLogCountVisibleViaExistential() async throws {
        // Fails enough times to exhaust the writer's retries, so the batch is dropped and reported.
        let storage = FlakyStorage(failingFirst: 3)
        let service: any LogRService = LogR(storage: storage, cryptoService: try makeCrypto())

        service.info("x")
        await service.flush()

        // onDrop hops to the main actor via a Task, so allow the pending update to apply.
        for _ in 0 ..< 50 where service.droppedLogCount == 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(service.droppedLogCount == 1)
    }

    @Test("Backpressure bounds the pending buffer and accounts every shed entry")
    func testBackpressureBoundsBufferAndAccountsDrops() async throws {
        // Storage can't keep up: with a tiny pending cap, a fast burst must shed the excess.
        let storage = SlowStorage(delay: .milliseconds(50))
        // A plain `OSAllocatedUnfairLock` rather than `SafeMutex`: the latter is `~Copyable`, so it
        // can't be captured in the escaping `@Sendable` onDrop closure below.
        let droppedBox = OSAllocatedUnfairLock(initialState: 0)
        let writer = LogWriterActor(storage: storage,
                                    cryptoService: try makeCrypto(),
                                    configuration: .default,
                                    batchSize: 5,
                                    maxRetries: 1,
                                    maxPendingWrites: 10)
        await writer.setOnDrop { count in droppedBox.withLock { $0 += count } }

        let total = 200
        for index in 0 ..< total {
            writer.ingest(LogEntry(level: .info, category: .system, subsystem: "t", message: "m\(index)"))
        }
        await writer.flush()

        let stored = await storage.storedCount
        let dropped = droppedBox.withLock { $0 }
        // Every entry is either persisted or accounted as a backpressure drop — none vanish silently.
        #expect(stored + dropped == total)
        // The buffer shed load instead of growing without bound.
        #expect(dropped > 0)
    }
}
