import Foundation
import os
import Security
import Testing
@testable import Logr
import LogrTesting

/// Storage opened lazily, entries buffered while the key or the storage cannot be read, and the status reported
/// meanwhile. `signal` stands in for the protected-data notification; the 30-second retry timer never fires here.
@MainActor
@Suite("Persistence status", .timeLimit(.minutes(1)))
struct PersistenceStatusTests {
    private let directory: TemporaryDirectory
    private let signals: AsyncStream<Void>
    private let signal: AsyncStream<Void>.Continuation
    private let configuration = LogrConfiguration(mirrorToOSLog: false)

    init() throws {
        directory = try TemporaryDirectory()
        (signals, signal) = AsyncStream<Void>.makeStream()
    }

    private func makeLogger(_ storage: LogStorage, keychain: any KeychainStore) -> LogR {
        LogR(storage: storage, cryptoService: LoggerCryptoService(store: keychain), configuration: configuration,
             analyser: nil, retrySignals: signals)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, *)
    private func status(of logger: LogR, becoming expected: PersistenceStatus) async {
        _ = await Observations { logger.persistenceStatus }.first { @Sendable in $0 == expected }
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, *)
    @Test func entriesWaitInMemoryWhileTheKeychainIsLockedAndPersistOnceItIsNot() async throws {
        let keychain = LockableKeychainStore(isLocked: true)
        let storage = FlakyStorage(failingFirst: 0)
        let logger = makeLogger(.custom(storage), keychain: keychain)

        for index in 1 ... 3 {
            logger.info("before unlock \(index)")
        }
        await status(of: logger, becoming: .waitingForProtectedData)
        await logger.flush()

        #expect(logger.recentLogs.count == 3)
        #expect(await storage.storedCount == 0)
        #expect(logger.droppedLogCount == 0)

        keychain.unlock()
        signal.yield()
        await status(of: logger, becoming: .active)
        await logger.flush()

        let crypto = LoggerCryptoService(store: keychain.base)
        let stored: [LogEntry] = try await storage.entries.map { try crypto.symmetricDecrypt(encryptedData: $0.data) }
        #expect(stored.map(\.message) == ["before unlock 1", "before unlock 2", "before unlock 3"])
        #expect(logger.droppedLogCount == 0)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, *)
    @Test func historyLoadsOnceTheKeyCanBeRead() async throws {
        let keychain = LockableKeychainStore(isLocked: false)
        let historical = LogEntry(level: .info, category: .system, subsystem: "test", message: "history")
        let storage = FlakyStorage(failingFirst: 0)
        try await storage.store(EncryptedLogEntry(id: historical.id, timestamp: historical.timestamp,
                                                  data: LoggerCryptoService(store: keychain.base)
                                                      .symmetricEncrypt(object: historical)))
        let locked = LockableKeychainStore(base: keychain.base, isLocked: true)
        let logger = makeLogger(.custom(storage), keychain: locked)

        logger.info("live")
        await status(of: logger, becoming: .waitingForProtectedData)
        #expect(logger.recentLogs.map(\.message) == ["live"])

        locked.unlock()
        signal.yield()
        _ = await Observations { logger.recentLogs }.first { @Sendable in $0.count == 2 }

        #expect(logger.recentLogs.map(\.message) == ["live", "history"])
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, *)
    @Test func aClearWhileTheKeyIsLockedEmptiesStorageAtOnce() async throws {
        let keychain = LockableKeychainStore(isLocked: false)
        let old = LogEntry(level: .info, category: .system, subsystem: "test", message: "before clear")
        let storage = FlakyStorage(failingFirst: 0)
        try await storage.store(EncryptedLogEntry(id: old.id, timestamp: old.timestamp,
                                                  data: LoggerCryptoService(store: keychain.base)
                                                      .symmetricEncrypt(object: old)))
        let locked = LockableKeychainStore(base: keychain.base, isLocked: true)
        let logger = makeLogger(.custom(storage), keychain: locked)
        logger.info("cleared before it was written")
        await status(of: logger, becoming: .waitingForProtectedData)

        try await logger.clearLogs()
        // Clearing needs no key, so it must not wait for the unlock (the app may be killed before it).
        #expect(await storage.storedCount == 0)
        logger.info("after clear")
        locked.unlock()
        signal.yield()
        await status(of: logger, becoming: .active)
        await logger.flush()

        #expect(logger.recentLogs.map(\.message) == ["after clear"])
        let crypto = LoggerCryptoService(store: keychain.base)
        let stored: [LogEntry] = try await storage.entries.map { try crypto.symmetricDecrypt(encryptedData: $0.data) }
        #expect(stored.map(\.message) == ["after clear"])
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, *)
    @Test func storageThatCannotBeOpenedIsRetried() async throws {
        // A regular file where the storage's directory should be makes opening fail.
        let blocker = directory.url.appendingPathComponent("blocked")
        try Data().write(to: blocker)
        let fileURL = blocker.appendingPathComponent("logs.ndjson")
        let keychain = InMemoryKeychainStore()
        let logger = makeLogger(.file(fileURL), keychain: keychain)
        logger.info("while storage is unavailable")

        _ = await Observations { logger.persistenceStatus }.first { @Sendable status in
            if case .failed = status { true } else { false }
        }
        try FileManager.default.removeItem(at: blocker)
        signal.yield()
        await status(of: logger, becoming: .active)
        await logger.flush()

        let stored = try await FileSystemStorage(directory: blocker, fileName: "logs.ndjson").fetchEntries()
        let entry: LogEntry = try LoggerCryptoService(store: keychain).symmetricDecrypt(encryptedData: stored[0].data)
        #expect(stored.count == 1)
        #expect(entry.message == "while storage is unavailable")
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, *)
    @Test func aClearBeforeStorageCanOpenIsAppliedWhenItOpens() async throws {
        let url = directory.url.appendingPathComponent("logs.sqlite")
        let keychain = InMemoryKeychainStore()
        let old = LogEntry(level: .info, category: .system, subsystem: "test", message: "before clear")
        try await SQLiteStorage(databasePath: url.path)
            .store(EncryptedLogEntry(id: old.id, timestamp: old.timestamp,
                                     data: LoggerCryptoService(store: keychain).symmetricEncrypt(object: old)))
        // An unreadable file stands in for a data-protected one before the first unlock.
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        let logger = makeLogger(.sqlite(url), keychain: keychain)
        _ = await Observations { logger.persistenceStatus }.first { @Sendable status in
            if case .failed = status { true } else { false }
        }

        try await logger.clearLogs()
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        signal.yield()
        await status(of: logger, becoming: .active)
        await logger.flush()

        #expect(try await SQLiteStorage(databasePath: url.path).count() == 0)
        #expect(logger.recentLogs.isEmpty)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, *)
    @Test func aHistoryReadFailureDoesNotStopWriting() async throws {
        let storage = FetchFailingStorage()
        let logger = makeLogger(.custom(storage), keychain: InMemoryKeychainStore())

        logger.info("written anyway")
        await logger.flush()

        #expect(await storage.storedCount == 1)
        await status(of: logger, becoming: .active)
    }

    @Test(arguments: ["sqlite", "file"])
    func storageOpensAtTheGivenURL(kind: String) async throws {
        let url = directory.url.appendingPathComponent("nested/logs.\(kind)")
        let storage: LogStorage = kind == "sqlite" ? .sqlite(url) : .file(url)
        let logger = makeLogger(storage, keychain: InMemoryKeychainStore())

        logger.info("at the given URL")
        await logger.flush()

        let reopened = try #require(try storage.open())
        #expect(try await reopened.count() == 1)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, *)
    @Test func aDamagedKeyRecordFailsVisiblyAndCountsEveryEntry() async throws {
        let keychain = InMemoryKeychainStore(items: ["logger_current_key_version": Data("not a version".utf8)])
        let storage = FlakyStorage(failingFirst: 0)
        let logger = makeLogger(.custom(storage), keychain: keychain)

        logger.info("one")
        logger.info("two")
        await logger.flush()

        _ = await Observations { logger.droppedLogCount }.first { @Sendable in $0 == 2 }
        await status(of: logger, becoming: .failed(String(describing: LoggerCryptoError.corruptKeyVersion)))
        #expect(await storage.storedCount == 0)
        #expect(logger.recentLogs.count == 2)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, *)
    @Test func aKeychainThatKeepsFailingIsAskedForTheKeyVersionOnce() async throws {
        let keychain = FailingKeychainStore(status: errSecMissingEntitlement)
        let storage = FlakyStorage(failingFirst: 0)
        let logger = makeLogger(.custom(storage), keychain: keychain)

        for index in 1 ... 200 {
            logger.info("entry \(index)")
        }
        await logger.flush()

        _ = await Observations { logger.droppedLogCount }.first { @Sendable in $0 == 200 }
        await status(of: logger, becoming: .failed(String(describing: KeychainError.status(errSecMissingEntitlement))))
        #expect(keychain.calls == 1)
        #expect(await storage.storedCount == 0)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, *)
    @Test func aBatchDroppedAfterFailedWritesReportsFailedUntilTheNextWrite() async throws {
        // Fails exactly the writer's three attempts for the first batch.
        let storage = FlakyStorage(failingFirst: 3)
        let logger = makeLogger(.custom(storage), keychain: InMemoryKeychainStore())

        logger.info("dropped")
        await logger.flush()
        await status(of: logger, becoming: .failed(String(describing: FlakyStorage.StorageError.transient)))

        logger.info("written")
        await logger.flush()
        await status(of: logger, becoming: .active)
        #expect(await storage.storedCount == 1)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, *)
    @Test(arguments: [true, false])
    func aNewLoggerReportsOpeningUntilItsFirstAttemptEnds(keychainIsLocked: Bool) async {
        let logger = makeLogger(.custom(FlakyStorage(failingFirst: 0)),
                                keychain: LockableKeychainStore(isLocked: keychainIsLocked))

        #expect(logger.persistenceStatus == .opening)
        await status(of: logger, becoming: keychainIsLocked ? .waitingForProtectedData : .active)
    }

    @Test func noStorageIsReportedAsDisabled() {
        #expect(LogR(cryptoService: LoggerCryptoService(store: InMemoryKeychainStore())).persistenceStatus == .disabled)
    }
}

@Suite("Writer backpressure while waiting")
struct WaitingWriterBackpressureTests {
    @Test(.timeLimit(.minutes(1)))
    func entriesBeyondTheCapAreShedAndTheRestPersistAfterTheUnlock() async throws {
        let keychain = LockableKeychainStore(isLocked: true)
        let storage = FlakyStorage(failingFirst: 0)
        let (signals, signal) = AsyncStream<Void>.makeStream()
        let writer = LogWriterActor(storage: .custom(storage),
                                    cryptoService: LoggerCryptoService(store: keychain),
                                    configuration: .default,
                                    maxPendingWrites: 5,
                                    retrySignals: signals)
        defer { writer.shutdown() }
        let (statuses, statusContinuation) = AsyncStream<PersistenceStatus>.makeStream()
        var statusUpdates = statuses.makeAsyncIterator()
        await writer.setOnStatus { statusContinuation.yield($0) }
        let dropped = OSAllocatedUnfairLock(initialState: 0)
        await writer.setOnDrop { count in dropped.withLock { $0 += count } }

        let entries = (1 ... 8).map { LogEntry(level: .info, category: .system, subsystem: "t", message: "m\($0)") }
        for entry in entries {
            writer.ingest(entry)
        }
        await writer.flush()
        #expect(dropped.withLock { $0 } == 3)
        #expect(await storage.storedCount == 0)
        while let status = await statusUpdates.next(), status != .waitingForProtectedData {}

        keychain.unlock()
        signal.yield()
        while let status = await statusUpdates.next(), status != .active {}
        await writer.flush()

        #expect(await storage.entries.map(\.id) == entries.prefix(5).map(\.id))
        #expect(dropped.withLock { $0 } == 3)
    }

    @Test(.timeLimit(.minutes(1)))
    func aStatusThatFailedOnWritesOnlyReturnsToActiveAfterAWrite() async throws {
        let writer = LogWriterActor(storage: .custom(FlakyStorage(failingFirst: .max)),
                                    cryptoService: LoggerCryptoService(store: InMemoryKeychainStore()),
                                    configuration: .default,
                                    retrySignals: AsyncStream { $0.finish() })
        defer { writer.shutdown() }
        await writer.flush()
        let statuses = OSAllocatedUnfairLock<[PersistenceStatus]>(initialState: [])
        await writer.setOnStatus { status in statuses.withLock { $0.append(status) } }

        for message in ["first", "second"] {
            writer.ingest(LogEntry(level: .info, category: .system, subsystem: "t", message: message))
            await writer.flush()
        }

        #expect(statuses.withLock { $0 } == [.active, .failed(String(describing: FlakyStorage.StorageError.transient))])
    }

    @Test(.timeLimit(.minutes(1)))
    func theWriterReportsOpeningUntilItsFirstAttemptEnds() async throws {
        let storage = GatedHistoryStorage()
        let writer = LogWriterActor(storage: .custom(storage),
                                    cryptoService: LoggerCryptoService(store: InMemoryKeychainStore()),
                                    configuration: .default,
                                    retrySignals: AsyncStream { _ in })
        defer { writer.shutdown() }
        let (statuses, statusContinuation) = AsyncStream<PersistenceStatus>.makeStream()
        var statusUpdates = statuses.makeAsyncIterator()
        await writer.setOnStatus { statusContinuation.yield($0) }

        #expect(await statusUpdates.next() == .opening)
        await storage.releaseHistory()
        #expect(await statusUpdates.next() == .active)
    }

    @Test(.timeLimit(.minutes(1)))
    func everyCallerWaitingForHistoryGetsIt() async throws {
        let keychain = LockableKeychainStore(isLocked: true)
        let (signals, signal) = AsyncStream<Void>.makeStream()
        let writer = LogWriterActor(storage: .custom(FlakyStorage(failingFirst: 0)),
                                    cryptoService: LoggerCryptoService(store: keychain),
                                    configuration: .default,
                                    retrySignals: signals)
        defer { writer.shutdown() }

        async let first = writer.persistedHistory()
        async let second = writer.persistedHistory()
        await writer.flush()
        keychain.unlock()
        signal.yield()

        let histories = await [first, second]
        #expect(histories.count == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func entriesShedWhileStorageCannotOpenAreReportedWithoutAFlush() async throws {
        let directory = try TemporaryDirectory()
        // A file where the storage's directory should be, so it never opens.
        let blocker = directory.url.appendingPathComponent("blocked")
        try Data().write(to: blocker)
        let writer = LogWriterActor(storage: .file(blocker.appendingPathComponent("logs.ndjson")),
                                    cryptoService: LoggerCryptoService(store: InMemoryKeychainStore()),
                                    configuration: .default,
                                    maxPendingWrites: 5,
                                    retrySignals: AsyncStream { _ in })
        defer { writer.shutdown() }
        let (drops, dropContinuation) = AsyncStream<Int>.makeStream()
        await writer.setOnDrop { dropContinuation.yield($0) }

        for index in 1 ... 8 {
            writer.ingest(LogEntry(level: .info, category: .system, subsystem: "t", message: "m\(index)"))
        }

        var dropped = 0
        for await count in drops {
            dropped += count
            if dropped >= 3 { break }
        }
        #expect(dropped == 3)
    }

    @Test(.timeLimit(.minutes(1)))
    func writingWhatWasEncryptedBeforeTheKeyLockedKeepsTheStatusWaiting() async throws {
        let storage = FlakyStorage(failingFirst: 0)
        // The key probe and "encrypted" take the two encryptions; "waiting" finds the key locked.
        let writer = LogWriterActor(storage: .custom(storage),
                                    cryptoService: KeyLockingCrypto(encryptionsBeforeLock: 2),
                                    configuration: .default,
                                    retrySignals: AsyncStream { _ in })
        defer { writer.shutdown() }
        await writer.flush()
        let statuses = OSAllocatedUnfairLock<[PersistenceStatus]>(initialState: [])
        await writer.setOnStatus { status in statuses.withLock { $0.append(status) } }

        for message in ["encrypted", "waiting"] {
            writer.ingest(LogEntry(level: .info, category: .system, subsystem: "t", message: message))
        }
        await writer.flush()

        #expect(await storage.storedCount == 1)
        #expect(statuses.withLock { $0 } == [.active, .waitingForProtectedData])
    }
}

/// Fails every call with `status`, as the Keychain does for an app missing the entitlement for its access group.
private final class FailingKeychainStore: KeychainStore {
    private let status: OSStatus
    private let callCount = OSAllocatedUnfairLock(initialState: 0)

    init(status: OSStatus) {
        self.status = status
    }

    var calls: Int { callCount.withLock { $0 } }

    func data(forKey key: String) throws -> Data? { try fail() }
    func set(_ data: Data, forKey key: String) throws { try fail() }
    func add(_ data: Data, forKey key: String) throws -> Bool { try fail() }
    func remove(forKey key: String) throws { try fail() }

    private func fail() throws -> Never {
        callCount.withLock { $0 += 1 }
        throw KeychainError.status(status)
    }
}

/// Encrypts until `encryptionsBeforeLock` encryptions have run, then reports the key as temporarily unavailable,
/// as a custom service may when the device locks again.
private final class KeyLockingCrypto: LoggerCryptoServicing {
    private let base = LoggerCryptoService(store: InMemoryKeychainStore())
    private let encryptionsLeft: OSAllocatedUnfairLock<Int>

    init(encryptionsBeforeLock: Int) {
        encryptionsLeft = OSAllocatedUnfairLock(initialState: encryptionsBeforeLock)
    }

    func symmetricEncrypt(object: some Codable & Sendable) throws -> Data {
        let isLocked = encryptionsLeft.withLock { left -> Bool in
            guard left > 0 else { return true }
            left -= 1
            return false
        }
        if isLocked {
            throw LoggerCryptoError.keyTemporarilyUnavailable
        }
        return try base.symmetricEncrypt(object: object)
    }

    func symmetricDecrypt<T: Codable & Sendable>(encryptedData: Data) throws -> T {
        try base.symmetricDecrypt(encryptedData: encryptedData)
    }
}

/// Holds the history read until `releaseHistory()`, so the writer's first open attempt can be kept running.
private actor GatedHistoryStorage: LogRPersistence {
    private var isReleased = false
    private var gate: CheckedContinuation<Void, Never>?

    func releaseHistory() {
        isReleased = true
        gate?.resume()
        gate = nil
    }

    func fetchEntries() async throws -> [EncryptedLogEntry] {
        if !isReleased {
            await withCheckedContinuation { gate = $0 }
        }
        return []
    }

    func store(_ entry: EncryptedLogEntry) async throws {}
    func deleteEntries(olderThan date: Date) async throws {}
    func deleteEntries(keepingLatest count: Int) async throws {}
    func clear() async throws {}
    func count() async throws -> Int { 0 }
}

/// Stores entries but cannot read them back, like a backend whose query path is down.
private actor FetchFailingStorage: LogRPersistence {
    struct FetchError: Error {}
    private var entries: [EncryptedLogEntry] = []

    var storedCount: Int { entries.count }

    func store(_ entry: EncryptedLogEntry) async throws { entries.append(entry) }
    func fetchEntries() async throws -> [EncryptedLogEntry] { throw FetchError() }
    func deleteEntries(olderThan date: Date) async throws {}
    func deleteEntries(keepingLatest count: Int) async throws {}
    func clear() async throws { entries.removeAll() }
    func count() async throws -> Int { entries.count }
}
