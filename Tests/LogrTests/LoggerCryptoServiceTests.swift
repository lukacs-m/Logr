import Testing
@testable import Logr
import LogrTesting
import Foundation
import CryptoKit
import os

@Suite("LoggerCryptoService Tests")
struct LoggerCryptoServiceTests {
    // MARK: - Initialization Tests

    @Test("Creating a service reads nothing; the first encryption creates key version 1")
    func testCryptoServiceInitialization() throws {
        let store = InMemoryKeychainStore()
        let cryptoService = LoggerCryptoService(store: store)
        #expect(store.items.isEmpty)
        #expect(cryptoService.currentKeyVersion.value == nil)

        _ = try cryptoService.symmetricEncrypt(object: "first")

        #expect(cryptoService.currentKeyVersion.value == KeyVersion(1))
        #expect(Set(store.items.keys) == ["logger_current_key_version", "logger_sym_key_v1"])
    }

    @Test("A second service on the same store adopts the stored key")
    func testCryptoServiceInitializationWithExistingKey() throws {
        let store = InMemoryKeychainStore()
        let encrypted = try LoggerCryptoService(store: store).symmetricEncrypt(object: "shared")
        let items = store.items

        let second = LoggerCryptoService(store: store)
        let decrypted: String = try second.symmetricDecrypt(encryptedData: try second.symmetricEncrypt(object: "shared"))

        #expect(decrypted == "shared")
        #expect(try second.symmetricDecrypt(encryptedData: encrypted) as String == "shared")
        #expect(store.items == items)
    }

    /// A custom store may report the lock with Logr's own error, or as an `NSError` like stores ported from 1.x.
    @Test("A locked Keychain throws keyTemporarilyUnavailable, never replaces the key, and works once unlocked",
          arguments: [KeychainError.status(errSecInteractionNotAllowed), LoggerCryptoError.keyTemporarilyUnavailable,
                      NSError(domain: NSOSStatusErrorDomain, code: Int(errSecInteractionNotAllowed))] as [any Error])
    func testLockedKeychainIsTemporary(lockError: any Error) throws {
        let base = InMemoryKeychainStore()
        let earlier = try LoggerCryptoService(store: base).symmetricEncrypt(object: "before reboot")
        let provisioned = base.items
        let store = LockableKeychainStore(base: base, isLocked: true, lockError: lockError)
        let cryptoService = LoggerCryptoService(store: store)

        #expect(throws: LoggerCryptoError.keyTemporarilyUnavailable) {
            _ = try cryptoService.symmetricEncrypt(object: "while locked")
        }
        #expect(throws: LoggerCryptoError.keyTemporarilyUnavailable) {
            let _: String = try cryptoService.symmetricDecrypt(encryptedData: earlier)
        }
        #expect(throws: LoggerCryptoError.keyTemporarilyUnavailable) { try cryptoService.rotateKey() }
        // Treating the error as "first run" would create a key over this one and orphan every stored log.
        #expect(base.items == provisioned)

        store.unlock()

        #expect(try cryptoService.symmetricDecrypt(encryptedData: earlier) as String == "before reboot")
        let after = try cryptoService.symmetricEncrypt(object: "after unlock")
        #expect(try LoggerCryptoService(store: base).symmetricDecrypt(encryptedData: after) as String == "after unlock")
        #expect(base.items == provisioned)
    }

    // MARK: - Encryption Tests

    @Test("Test symmetric encryption")
    func testSymmetricEncryption() async throws {
        let mockStore = InMemoryKeychainStore()
        let cryptoService = LoggerCryptoService(store: mockStore)

        let testData = "Hello, World!"
        let encryptedData = try cryptoService.symmetricEncrypt(object: testData)

        #expect(!encryptedData.isEmpty)
        // Encrypted data should be different from original
        #expect(encryptedData != testData.data(using: .utf8)!)
    }

    @Test("Test encrypt log entry")
    func testEncryptLogEntry() async throws {
        let mockStore = InMemoryKeychainStore()
        let cryptoService = LoggerCryptoService(store: mockStore)

        let logEntry = LogEntry(
            level: .info,
            category: .system,
            subsystem: "com.test",
            message: "Test log message"
        )

        let encryptedData = try cryptoService.symmetricEncrypt(object: logEntry)

        #expect(!encryptedData.isEmpty)
    }

    @Test("Test encrypt empty string")
    func testEncryptEmptyString() async throws {
        let mockStore = InMemoryKeychainStore()
        let cryptoService = LoggerCryptoService(store: mockStore)

        let emptyString = ""
        let encryptedData = try cryptoService.symmetricEncrypt(object: emptyString)

        #expect(!encryptedData.isEmpty)
    }

    @Test("Test encrypt large data")
    func testEncryptLargeData() async throws {
        let mockStore = InMemoryKeychainStore()
        let cryptoService = LoggerCryptoService(store: mockStore)

        let largeString = String(repeating: "A", count: 100000)
        let encryptedData = try cryptoService.symmetricEncrypt(object: largeString)

        #expect(!encryptedData.isEmpty)
    }

    @Test("Test encrypt unicode data")
    func testEncryptUnicodeData() async throws {
        let mockStore = InMemoryKeychainStore()
        let cryptoService = LoggerCryptoService(store: mockStore)

        let unicodeString = "Hello 世界 🌍 مرحبا"
        let encryptedData = try cryptoService.symmetricEncrypt(object: unicodeString)

        #expect(!encryptedData.isEmpty)
    }

    // MARK: - Decryption Tests

    @Test("Test symmetric decryption")
    func testSymmetricDecryption() async throws {
        let mockStore = InMemoryKeychainStore()
        let cryptoService = LoggerCryptoService(store: mockStore)

        let originalText = "Hello, World!"
        let encryptedData = try cryptoService.symmetricEncrypt(object: originalText)
        let decryptedText: String = try cryptoService.symmetricDecrypt(encryptedData: encryptedData)

        #expect(decryptedText == originalText)
    }

    @Test("Test decrypt log entry")
    func testDecryptLogEntry() async throws {
        let mockStore = InMemoryKeychainStore()
        let cryptoService = LoggerCryptoService(store: mockStore)

        let originalEntry = LogEntry(
            level: .error,
            category: .network,
            subsystem: "com.test",
            message: "Network error occurred"
        )

        let encryptedData = try cryptoService.symmetricEncrypt(object: originalEntry)
        let decryptedEntry: LogEntry = try cryptoService.symmetricDecrypt(encryptedData: encryptedData)

        #expect(decryptedEntry.level == originalEntry.level)
        #expect(decryptedEntry.category == originalEntry.category)
        #expect(decryptedEntry.subsystem == originalEntry.subsystem)
        #expect(decryptedEntry.message == originalEntry.message)
    }

    @Test("Test decrypt empty string")
    func testDecryptEmptyString() async throws {
        let mockStore = InMemoryKeychainStore()
        let cryptoService = LoggerCryptoService(store: mockStore)

        let emptyString = ""
        let encryptedData = try cryptoService.symmetricEncrypt(object: emptyString)
        let decryptedString: String = try cryptoService.symmetricDecrypt(encryptedData: encryptedData)

        #expect(decryptedString == emptyString)
    }

    @Test("Test decrypt large data")
    func testDecryptLargeData() async throws {
        let mockStore = InMemoryKeychainStore()
        let cryptoService = LoggerCryptoService(store: mockStore)

        let largeString = String(repeating: "B", count: 100000)
        let encryptedData = try cryptoService.symmetricEncrypt(object: largeString)
        let decryptedString: String = try cryptoService.symmetricDecrypt(encryptedData: encryptedData)

        #expect(decryptedString == largeString)
    }

    @Test("Test decrypt unicode data")
    func testDecryptUnicodeData() async throws {
        let mockStore = InMemoryKeychainStore()
        let cryptoService = LoggerCryptoService(store: mockStore)

        let unicodeString = "Hello 世界 🌍 مرحبا"
        let encryptedData = try cryptoService.symmetricEncrypt(object: unicodeString)
        let decryptedString: String = try cryptoService.symmetricDecrypt(encryptedData: encryptedData)

        #expect(decryptedString == unicodeString)
    }

    // MARK: - Round Trip Tests

    @Test("Test encrypt-decrypt round trip")
    func testEncryptDecryptRoundTrip() async throws {
        let mockStore = InMemoryKeychainStore()
        let cryptoService = LoggerCryptoService(store: mockStore)

        let testStrings = [
            "Simple text",
            "Text with special chars: !@#$%^&*()",
            "Multi\nline\ntext",
            "Unicode: 你好世界",
            "",
            String(repeating: "X", count: 1000)
        ]

        for testString in testStrings {
            let encryptedData = try cryptoService.symmetricEncrypt(object: testString)
            let decryptedString: String = try cryptoService.symmetricDecrypt(encryptedData: encryptedData)

            #expect(decryptedString == testString)
        }
    }

    @Test("Test encrypt-decrypt multiple log entries")
    func testEncryptDecryptMultipleLogEntries() async throws {
        let mockStore = InMemoryKeychainStore()
        let cryptoService = LoggerCryptoService(store: mockStore)

        let entries = [
            LogEntry(level: .debug, category: .debug, subsystem: "test", message: "Debug message"),
            LogEntry(level: .info, category: .system, subsystem: "test", message: "Info message"),
            LogEntry(level: .error, category: .network, subsystem: "test", message: "Error message"),
            LogEntry(level: .fault, category: .database, subsystem: "test", message: "Fault message")
        ]

        for originalEntry in entries {
            let encryptedData = try cryptoService.symmetricEncrypt(object: originalEntry)
            let decryptedEntry: LogEntry = try cryptoService.symmetricDecrypt(encryptedData: encryptedData)

            #expect(decryptedEntry.level == originalEntry.level)
            #expect(decryptedEntry.category == originalEntry.category)
            #expect(decryptedEntry.message == originalEntry.message)
        }
    }

    // MARK: - Key Rotation Tests

    @Test("Test key rotation")
    func testKeyRotation() async throws {
        let mockStore = InMemoryKeychainStore()
        let cryptoService = LoggerCryptoService(store: mockStore)

        // Encrypt with version 1
        let originalText = "Test message"
        let encryptedV1 = try cryptoService.symmetricEncrypt(object: originalText)
        #expect(cryptoService.currentKeyVersion.value?.value == 1)

        // Rotate key
        try cryptoService.rotateKey(removeOldKeys: false)

        #expect(cryptoService.currentKeyVersion.value?.value == 2)

        // Should still be able to decrypt old data
        let decryptedText: String = try cryptoService.symmetricDecrypt(encryptedData: encryptedV1)
        #expect(decryptedText == originalText)

        // New encryption should use new key
        let encryptedV2 = try cryptoService.symmetricEncrypt(object: originalText)
        let decryptedV2: String = try cryptoService.symmetricDecrypt(encryptedData: encryptedV2)
        #expect(decryptedV2 == originalText)
    }

    @Test("Test key rotation with removal of old keys")
    func testKeyRotationWithRemoval() async throws {
        let mockStore = InMemoryKeychainStore()
        let cryptoService = LoggerCryptoService(store: mockStore)

        // Encrypt with version 1
        let originalText = "Test message"
        _ = try cryptoService.symmetricEncrypt(object: originalText)

        // Rotate key and remove old key
        try cryptoService.rotateKey(removeOldKeys: true)

        #expect(cryptoService.currentKeyVersion.value?.value == 2)

        // New encryption should work
        let encryptedV2 = try cryptoService.symmetricEncrypt(object: originalText)
        let decryptedV2: String = try cryptoService.symmetricDecrypt(encryptedData: encryptedV2)
        #expect(decryptedV2 == originalText)
    }

    @Test("Test multiple key rotations")
    func testMultipleKeyRotations() async throws {
        let mockStore = InMemoryKeychainStore()
        let cryptoService = LoggerCryptoService(store: mockStore)
        // Unresolved until first use: the first rotation creates version 1, then moves to 2.
        #expect(cryptoService.currentKeyVersion.value == nil)

        for i in 2...5 {
            try cryptoService.rotateKey(removeOldKeys: false)
            #expect(cryptoService.currentKeyVersion.value?.value == i)
        }

        // Should be at version 5
        #expect(cryptoService.currentKeyVersion.value?.value == 5)
    }

    @Test("Rotation with removeOldKeys removes every older version, not only the previous one")
    func testRotationRemovesEveryOlderKey() throws {
        let store = InMemoryKeychainStore()
        let cryptoService = LoggerCryptoService(store: store)
        try cryptoService.rotateKey()
        try cryptoService.rotateKey()

        try cryptoService.rotateKey(removeOldKeys: true)

        #expect(store.items.keys.filter { $0.hasPrefix("logger_sym_key_v") } == ["logger_sym_key_v4"])
        let encrypted = try cryptoService.symmetricEncrypt(object: "after")
        let decrypted: String = try cryptoService.symmetricDecrypt(encryptedData: encrypted)
        #expect(decrypted == "after")
    }

    @Test("Rotation removes only stored keys, so a store that rejects unknown keys keeps working")
    func testRotationOnlyRemovesStoredKeys() throws {
        let base = InMemoryKeychainStore()
        let cryptoService = LoggerCryptoService(store: StrictRemovalKeychainStore(base: base))

        try cryptoService.rotateKey(removeOldKeys: true)
        try cryptoService.rotateKey(removeOldKeys: true)

        #expect(base.items.keys.filter { $0.hasPrefix("logger_sym_key_v") } == ["logger_sym_key_v3"])
    }

    @Test("Rotation stops at the last key version instead of writing one the next launch would reject")
    func testRotationStopsAtTheVersionCap() throws {
        let store = InMemoryKeychainStore(items: ["logger_current_key_version": Data(#"{"value":1000000}"#.utf8),
                                                  "logger_sym_key_v1000000": Data(repeating: 1, count: 32)])
        let cryptoService = LoggerCryptoService(store: store)
        let items = store.items

        #expect(throws: LoggerCryptoError.self) { try cryptoService.rotateKey() }

        #expect(store.items == items)
        #expect(cryptoService.currentKeyVersion.value == KeyVersion(1_000_000))
    }

    @Test("Rotation adopts a key already stored for the next version instead of replacing it")
    func testRotationNeverReplacesAnExistingKey() throws {
        let store = InMemoryKeychainStore()
        let cryptoService = LoggerCryptoService(store: store)
        let existingV2 = Data(repeating: 7, count: 32)
        try store.set(existingV2, forKey: "logger_sym_key_v2")

        try cryptoService.rotateKey()

        #expect(store.items["logger_sym_key_v2"] == existingV2)
    }

    @Test("Rotation removes old keys after releasing the key lock that encryption waits on")
    func testRotationCleanupRunsOffTheKeyLock() throws {
        let store = RemovalHookKeychainStore()
        let cryptoService = LoggerCryptoService(store: store)
        try cryptoService.rotateKey()
        try cryptoService.rotateKey()
        let lockWasFree = OSAllocatedUnfairLock<[Bool]>(initialState: [])
        store.onRemove { _ in
            let free = cryptoService.currentKeyVersion.withLockIfAvailable { _ in true } ?? false
            lockWasFree.withLock { $0.append(free) }
        }
        defer { store.onRemove(nil) }

        try cryptoService.rotateKey(removeOldKeys: true)

        #expect(lockWasFree.withLock { $0 } == [true, true, true])
    }

    @Test("A key version being removed cannot be read back into the cache while the removal runs")
    func testRemovedVersionsStayUnreadableDuringCleanup() throws {
        let store = RemovalHookKeychainStore()
        let cryptoService = LoggerCryptoService(store: store)
        let oldEntry = try cryptoService.symmetricEncrypt(object: "v1")
        let readableDuringCleanup = OSAllocatedUnfairLock<[Bool]>(initialState: [])
        store.onRemove { _ in
            let readable = (try? cryptoService.symmetricDecrypt(encryptedData: oldEntry) as String) != nil
            readableDuringCleanup.withLock { $0.append(readable) }
        }
        defer { store.onRemove(nil) }

        try cryptoService.rotateKey(removeOldKeys: true)

        #expect(readableDuringCleanup.withLock { $0 } == [false])
        #expect(throws: LoggerCryptoError.self) {
            let _: String = try cryptoService.symmetricDecrypt(encryptedData: oldEntry)
        }
    }

    // MARK: - Key Provisioning (never overwrite)

    @Test("A key another service adds between our read and our add is adopted, not replaced")
    func testKeyAddedConcurrentlyIsAdopted() throws {
        let theirs = Data(repeating: 9, count: 32)
        let base = InMemoryKeychainStore(items: ["logger_sym_key_v1": theirs])

        let cryptoService = LoggerCryptoService(store: FirstReadMissesKeychainStore(base: base))

        #expect(base.items["logger_sym_key_v1"] == theirs)
        let encrypted = try cryptoService.symmetricEncrypt(object: "shared")
        let decrypted: String = try LoggerCryptoService(store: base).symmetricDecrypt(encryptedData: encrypted)
        #expect(decrypted == "shared")
    }

    @Test("InMemoryKeychainStore.add keeps an item that is already stored")
    func testInMemoryAddKeepsTheStoredItem() throws {
        let store = InMemoryKeychainStore()

        #expect(try store.add(Data([1]), forKey: "key"))
        #expect(try !store.add(Data([2]), forKey: "key"))
        #expect(store.items == ["key": Data([1])])
    }

    @Test("A key without its version record is adopted, not regenerated")
    func testKeyWithoutVersionRecordIsAdopted() throws {
        var items = try LegacyFixtures.keychain().items
        items["logger_current_key_version"] = nil
        let store = InMemoryKeychainStore(items: items)

        let cryptoService = LoggerCryptoService(store: store)
        _ = try cryptoService.symmetricEncrypt(object: "resolves the version")

        #expect(store.items["logger_sym_key_v1"] == items["logger_sym_key_v1"])
        #expect(cryptoService.currentKeyVersion.value == KeyVersion(1))
        let envelope = try Data(contentsOf: LegacyFixtures.url("legacy-envelope-chacha-no-algorithm.json"))
        let entry: LogEntry = try cryptoService.symmetricDecrypt(encryptedData: envelope)
        #expect(entry == LegacyFixtures.entries[0])
    }

    @Test("A damaged version record throws corruptKeyVersion instead of regenerating the key",
          arguments: ["not a version", #"{"value":0}"#, #"{"value":-2}"#, #"{"value":1000001}"#])
    func testCorruptVersionRecordThrows(record: String) throws {
        var items = try LegacyFixtures.keychain().items
        items["logger_current_key_version"] = Data(record.utf8)
        let store = InMemoryKeychainStore(items: items)
        let cryptoService = LoggerCryptoService(store: store)

        #expect(throws: LoggerCryptoError.corruptKeyVersion) {
            _ = try cryptoService.symmetricEncrypt(object: "new entry")
        }
        #expect(throws: LoggerCryptoError.corruptKeyVersion) { try cryptoService.rotateKey() }

        // The stored keys still decrypt earlier entries.
        let envelope = try Data(contentsOf: LegacyFixtures.url("legacy-envelope-chacha-no-algorithm.json"))
        let entry: LogEntry = try cryptoService.symmetricDecrypt(encryptedData: envelope)
        #expect(entry == LegacyFixtures.entries[0])
        #expect(store.items == items)
    }

    @Test("A damaged version record is read once, not on every encryption")
    func testCorruptVersionRecordIsReadOnce() throws {
        let store = ReadCountingKeychainStore(base: InMemoryKeychainStore(items: [
            "logger_current_key_version": Data("not a version".utf8)
        ]))
        let cryptoService = LoggerCryptoService(store: store)

        for _ in 1 ... 3 {
            #expect(throws: LoggerCryptoError.corruptKeyVersion) {
                _ = try cryptoService.symmetricEncrypt(object: "dropped")
            }
        }

        #expect(store.reads == 1)
    }

    // MARK: - Error Handling Tests

    @Test("Test decrypt with invalid data")
    func testDecryptWithInvalidData() async throws {
        let mockStore = InMemoryKeychainStore()
        let cryptoService = LoggerCryptoService(store: mockStore)

        let invalidData = Data([0x00, 0x01, 0x02, 0x03])

        #expect(throws: Error.self) {
            let _: String = try cryptoService.symmetricDecrypt(encryptedData: invalidData)
        }
    }

    @Test("Test decrypt with corrupted data")
    func testDecryptWithCorruptedData() async throws {
        let mockStore = InMemoryKeychainStore()
        let cryptoService = LoggerCryptoService(store: mockStore)

        let originalText = "Test message"
        var encryptedData = try cryptoService.symmetricEncrypt(object: originalText)

        // Corrupt the data
        encryptedData[5] = encryptedData[5] ^ 0xFF

        #expect(throws: Error.self) {
            let _: String = try cryptoService.symmetricDecrypt(encryptedData: encryptedData)
        }
    }

    // MARK: - Concurrent Access Tests

    @Test("Test concurrent encryption")
    func testConcurrentEncryption() async throws {
        let mockStore = InMemoryKeychainStore()
        let cryptoService = LoggerCryptoService(store: mockStore)

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    do {
                        let message = "Message \(i)"
                        _ = try cryptoService.symmetricEncrypt(object: message)
                    } catch {
                        Issue.record("Encryption failed: \(error)")
                    }
                }
            }
        }
    }

    @Test("Test concurrent encryption and decryption")
    func testConcurrentEncryptionAndDecryption() async throws {
        let mockStore = InMemoryKeychainStore()
        let cryptoService = LoggerCryptoService(store: mockStore)

        // Pre-encrypt some data
        let originalMessages = (0..<10).map { "Message \($0)" }
        var encryptedDataArray: [Data] = []

        for message in originalMessages {
            let encrypted = try cryptoService.symmetricEncrypt(object: message)
            encryptedDataArray.append(encrypted)
        }

        // Concurrently decrypt
        await withTaskGroup(of: Bool.self) { group in
            for (index, encryptedData) in encryptedDataArray.enumerated() {
                group.addTask {
                    do {
                        let decrypted: String = try cryptoService.symmetricDecrypt(encryptedData: encryptedData)
                        return decrypted == originalMessages[index]
                    } catch {
                        Issue.record("Decryption failed: \(error)")
                        return false
                    }
                }
            }

            var successCount = 0
            for await success in group {
                if success {
                    successCount += 1
                }
            }

            #expect(successCount == 10)
        }
    }

    // MARK: - Complex Object Tests

    @Test("Test encrypt decrypt complex log entry")
    func testEncryptDecryptComplexLogEntry() async throws {
        let mockStore = InMemoryKeychainStore()
        let cryptoService = LoggerCryptoService(store: mockStore)

        let complexEntry = LogEntry(
            id: "test-id-123",
            timestamp: Date(),
            level: .error,
            category: LogCategory(rawValue: "CustomCategory"),
            subsystem: "com.complex.test.app",
            message: "Complex message with special chars: !@#$%^&*() and unicode 世界",
            file: "/path/to/file.swift",
            function: "testFunction()",
            line: 42
        )

        let encryptedData = try cryptoService.symmetricEncrypt(object: complexEntry)
        let decryptedEntry: LogEntry = try cryptoService.symmetricDecrypt(encryptedData: encryptedData)

        #expect(decryptedEntry.id == complexEntry.id)
        #expect(decryptedEntry.level == complexEntry.level)
        #expect(decryptedEntry.category == complexEntry.category)
        #expect(decryptedEntry.subsystem == complexEntry.subsystem)
        #expect(decryptedEntry.message == complexEntry.message)
        #expect(decryptedEntry.file == complexEntry.file)
        #expect(decryptedEntry.function == complexEntry.function)
        #expect(decryptedEntry.line == complexEntry.line)
    }

    // MARK: - Key Version Tests

    @Test("Test key version initialization")
    func testKeyVersionInitialization() async throws {
        let version1 = KeyVersion(1)
        let version2 = KeyVersion(5)

        #expect(version1.value == 1)
        #expect(version2.value == 5)
    }

    @Test("Test default key version")
    func testDefaultKeyVersion() async throws {
        let defaultVersion = KeyVersion.default

        #expect(defaultVersion.value == 1)
    }
}

/// Fails every call with `lockError` (by default `errSecInteractionNotAllowed`, as the Keychain does before the
/// first unlock after a restart) until `unlock()`; then forwards to `base`.
final class LockableKeychainStore: KeychainStore {
    let base: InMemoryKeychainStore
    private let locked: OSAllocatedUnfairLock<Bool>
    private let lockError: any Error

    init(base: InMemoryKeychainStore = InMemoryKeychainStore(), isLocked: Bool,
         lockError: any Error = KeychainError.status(errSecInteractionNotAllowed)) {
        self.base = base
        locked = OSAllocatedUnfairLock(initialState: isLocked)
        self.lockError = lockError
    }

    func unlock() {
        locked.withLock { $0 = false }
    }

    func data(forKey key: String) throws -> Data? {
        try checkUnlocked()
        return try base.data(forKey: key)
    }

    func set(_ data: Data, forKey key: String) throws {
        try checkUnlocked()
        try base.set(data, forKey: key)
    }

    func add(_ data: Data, forKey key: String) throws -> Bool {
        try checkUnlocked()
        return try base.add(data, forKey: key)
    }

    func remove(forKey key: String) throws {
        try checkUnlocked()
        try base.remove(forKey: key)
    }

    private func checkUnlocked() throws {
        guard !locked.withLock({ $0 }) else { throw lockError }
    }
}

/// Throws when asked to remove a key it does not hold, as a strict custom store may.
private struct StrictRemovalKeychainStore: KeychainStore {
    struct MissingKey: Error {}

    let base: InMemoryKeychainStore

    func data(forKey key: String) throws -> Data? { try base.data(forKey: key) }
    func set(_ data: Data, forKey key: String) throws { try base.set(data, forKey: key) }
    func add(_ data: Data, forKey key: String) throws -> Bool { try base.add(data, forKey: key) }

    func remove(forKey key: String) throws {
        guard try base.data(forKey: key) != nil else { throw MissingKey() }
        try base.remove(forKey: key)
    }
}

/// Misses the first read of each key, as if another service stored the key just after that read.
private final class FirstReadMissesKeychainStore: KeychainStore {
    let base: InMemoryKeychainStore
    private let readKeys = OSAllocatedUnfairLock<Set<String>>(initialState: [])

    init(base: InMemoryKeychainStore) {
        self.base = base
    }

    func data(forKey key: String) throws -> Data? {
        guard readKeys.withLock({ $0.insert(key).inserted }) else { return try base.data(forKey: key) }
        return nil
    }

    func set(_ data: Data, forKey key: String) throws { try base.set(data, forKey: key) }
    func add(_ data: Data, forKey key: String) throws -> Bool { try base.add(data, forKey: key) }
    func remove(forKey key: String) throws { try base.remove(forKey: key) }
}

/// Calls the `onRemove` hook with each key just before removing it.
private final class RemovalHookKeychainStore: KeychainStore {
    private let base = InMemoryKeychainStore()
    private let hook = OSAllocatedUnfairLock<(@Sendable (String) -> Void)?>(initialState: nil)

    func onRemove(_ body: (@Sendable (String) -> Void)?) {
        hook.withLock { $0 = body }
    }

    func data(forKey key: String) throws -> Data? { try base.data(forKey: key) }
    func set(_ data: Data, forKey key: String) throws { try base.set(data, forKey: key) }
    func add(_ data: Data, forKey key: String) throws -> Bool { try base.add(data, forKey: key) }

    func remove(forKey key: String) throws {
        hook.withLock { $0 }?(key)
        try base.remove(forKey: key)
    }
}


/// Counts reads, then forwards everything to `base`.
private final class ReadCountingKeychainStore: KeychainStore {
    let base: InMemoryKeychainStore
    private let count = OSAllocatedUnfairLock(initialState: 0)

    init(base: InMemoryKeychainStore) {
        self.base = base
    }

    var reads: Int {
        count.withLock { $0 }
    }

    func data(forKey key: String) throws -> Data? {
        count.withLock { $0 += 1 }
        return try base.data(forKey: key)
    }

    func set(_ data: Data, forKey key: String) throws { try base.set(data, forKey: key) }
    func add(_ data: Data, forKey key: String) throws -> Bool { try base.add(data, forKey: key) }
    func remove(forKey key: String) throws { try base.remove(forKey: key) }
}
