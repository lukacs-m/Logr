import Testing
@testable import Logr
import Foundation
import CryptoKit

@Suite("LoggerCryptoService Tests")
struct LoggerCryptoServiceTests {
    // MARK: - Initialization Tests

    @Test("Test crypto service initialization")
    func testCryptoServiceInitialization() async throws {
        let mockStore = MockKeychainService()
        let cryptoService = LoggerCryptoService(store: mockStore)

        #expect(cryptoService.currentKeyVersion.value.value == 1)
    }

    @Test("Test crypto service initialization with existing key")
    func testCryptoServiceInitializationWithExistingKey() async throws {
        let mockStore = MockKeychainService()

        // First initialization
        _ = LoggerCryptoService(store: mockStore)

        // Second initialization should load existing key
        let cryptoService2 = LoggerCryptoService(store: mockStore)

        #expect(cryptoService2.currentKeyVersion.value.value == 1)
    }

    // MARK: - Encryption Tests

    @Test("Test symmetric encryption")
    func testSymmetricEncryption() async throws {
        let mockStore = MockKeychainService()
        let cryptoService = LoggerCryptoService(store: mockStore)

        let testData = "Hello, World!"
        let encryptedData = try cryptoService.symmetricEncrypt(object: testData)

        #expect(!encryptedData.isEmpty)
        // Encrypted data should be different from original
        #expect(encryptedData != testData.data(using: .utf8)!)
    }

    @Test("Test encrypt log entry")
    func testEncryptLogEntry() async throws {
        let mockStore = MockKeychainService()
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
        let mockStore = MockKeychainService()
        let cryptoService = LoggerCryptoService(store: mockStore)

        let emptyString = ""
        let encryptedData = try cryptoService.symmetricEncrypt(object: emptyString)

        #expect(!encryptedData.isEmpty)
    }

    @Test("Test encrypt large data")
    func testEncryptLargeData() async throws {
        let mockStore = MockKeychainService()
        let cryptoService = LoggerCryptoService(store: mockStore)

        let largeString = String(repeating: "A", count: 100000)
        let encryptedData = try cryptoService.symmetricEncrypt(object: largeString)

        #expect(!encryptedData.isEmpty)
    }

    @Test("Test encrypt unicode data")
    func testEncryptUnicodeData() async throws {
        let mockStore = MockKeychainService()
        let cryptoService = LoggerCryptoService(store: mockStore)

        let unicodeString = "Hello 世界 🌍 مرحبا"
        let encryptedData = try cryptoService.symmetricEncrypt(object: unicodeString)

        #expect(!encryptedData.isEmpty)
    }

    // MARK: - Decryption Tests

    @Test("Test symmetric decryption")
    func testSymmetricDecryption() async throws {
        let mockStore = MockKeychainService()
        let cryptoService = LoggerCryptoService(store: mockStore)

        let originalText = "Hello, World!"
        let encryptedData = try cryptoService.symmetricEncrypt(object: originalText)
        let decryptedText: String = try cryptoService.symmetricDecrypt(encryptedData: encryptedData)

        #expect(decryptedText == originalText)
    }

    @Test("Test decrypt log entry")
    func testDecryptLogEntry() async throws {
        let mockStore = MockKeychainService()
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
        let mockStore = MockKeychainService()
        let cryptoService = LoggerCryptoService(store: mockStore)

        let emptyString = ""
        let encryptedData = try cryptoService.symmetricEncrypt(object: emptyString)
        let decryptedString: String = try cryptoService.symmetricDecrypt(encryptedData: encryptedData)

        #expect(decryptedString == emptyString)
    }

    @Test("Test decrypt large data")
    func testDecryptLargeData() async throws {
        let mockStore = MockKeychainService()
        let cryptoService = LoggerCryptoService(store: mockStore)

        let largeString = String(repeating: "B", count: 100000)
        let encryptedData = try cryptoService.symmetricEncrypt(object: largeString)
        let decryptedString: String = try cryptoService.symmetricDecrypt(encryptedData: encryptedData)

        #expect(decryptedString == largeString)
    }

    @Test("Test decrypt unicode data")
    func testDecryptUnicodeData() async throws {
        let mockStore = MockKeychainService()
        let cryptoService = LoggerCryptoService(store: mockStore)

        let unicodeString = "Hello 世界 🌍 مرحبا"
        let encryptedData = try cryptoService.symmetricEncrypt(object: unicodeString)
        let decryptedString: String = try cryptoService.symmetricDecrypt(encryptedData: encryptedData)

        #expect(decryptedString == unicodeString)
    }

    // MARK: - Round Trip Tests

    @Test("Test encrypt-decrypt round trip")
    func testEncryptDecryptRoundTrip() async throws {
        let mockStore = MockKeychainService()
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
        let mockStore = MockKeychainService()
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
        let mockStore = MockKeychainService()
        let cryptoService = LoggerCryptoService(store: mockStore)

        #expect(cryptoService.currentKeyVersion.value.value == 1)

        // Encrypt with version 1
        let originalText = "Test message"
        let encryptedV1 = try cryptoService.symmetricEncrypt(object: originalText)

        // Rotate key
        try cryptoService.rotateKey(removeOldKeys: false)

        #expect(cryptoService.currentKeyVersion.value.value == 2)

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
        let mockStore = MockKeychainService()
        let cryptoService = LoggerCryptoService(store: mockStore)

        // Encrypt with version 1
        let originalText = "Test message"
        _ = try cryptoService.symmetricEncrypt(object: originalText)

        // Rotate key and remove old key
        try cryptoService.rotateKey(removeOldKeys: true)

        #expect(cryptoService.currentKeyVersion.value.value == 2)

        // New encryption should work
        let encryptedV2 = try cryptoService.symmetricEncrypt(object: originalText)
        let decryptedV2: String = try cryptoService.symmetricDecrypt(encryptedData: encryptedV2)
        #expect(decryptedV2 == originalText)
    }

    @Test("Test multiple key rotations")
    func testMultipleKeyRotations() async throws {
        let mockStore = MockKeychainService()
        let cryptoService = LoggerCryptoService(store: mockStore)

        #expect(cryptoService.currentKeyVersion.value.value == 1)

        for i in 2...5 {
            try cryptoService.rotateKey(removeOldKeys: false)
            #expect(cryptoService.currentKeyVersion.value.value == i)
        }

        // Should be at version 5
        #expect(cryptoService.currentKeyVersion.value.value == 5)
    }

    // MARK: - Error Handling Tests

    @Test("Test decrypt with invalid data")
    func testDecryptWithInvalidData() async throws {
        let mockStore = MockKeychainService()
        let cryptoService = LoggerCryptoService(store: mockStore)

        let invalidData = Data([0x00, 0x01, 0x02, 0x03])

        #expect(throws: Error.self) {
            let _: String = try cryptoService.symmetricDecrypt(encryptedData: invalidData)
        }
    }

    @Test("Test decrypt with corrupted data")
    func testDecryptWithCorruptedData() async throws {
        let mockStore = MockKeychainService()
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
        let mockStore = MockKeychainService()
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
        let mockStore = MockKeychainService()
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
        let mockStore = MockKeychainService()
        let cryptoService = LoggerCryptoService(store: mockStore)

        let complexEntry = LogEntry(
            id: "test-id-123",
            timestamp: Date(),
            level: .error,
            category: .custom("CustomCategory"),
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
