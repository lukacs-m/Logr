import Testing
@testable import Logr
import Foundation

@Suite("Concurrent Logging Tests")
struct ConcurrentLoggingTests {

    // MARK: - Helper to create test database

    func createTestDatabase() throws -> LogRepository {
        let tempDir = FileManager.default.temporaryDirectory
        let testDBPath = tempDir
            .appendingPathComponent("concurrent_test_\(UUID().uuidString).sqlite")
            .path
        return try LogRepository(databasePath: testDBPath)
    }

    func createMockCryptoService() -> LoggerCryptoService {
        return LoggerCryptoService(store: MockKeychainService())
    }

    // MARK: - Basic Concurrent Tests

    @MainActor
    @Test("Test concurrent logging from multiple threads - in memory")
    func testConcurrentLoggingInMemory() async throws {
        let logr = LogR(cryptoService: createMockCryptoService())
        let logCount = 100
        let threadCount = 10

        await withTaskGroup(of: Void.self) { group in
            for threadId in 0..<threadCount {
                group.addTask { @MainActor in
                    for i in 0..<logCount {
                        logr.info("Thread \(threadId) - Message \(i)", category: .test)
                    }
                }
            }
        }

        // Wait a bit for all logs to be processed
        try await Task.sleep(for: .milliseconds(100))

        // Verify all logs were captured
        let expectedTotal = logCount * threadCount
        #expect(logr.recentLogs.count == expectedTotal)
    }

    @MainActor
    @Test("Test concurrent logging with storage")
    func testConcurrentLoggingWithStorage() async throws {
        let storage = try createTestDatabase()
        let logr = LogR(
            storage: storage,
            cryptoService: createMockCryptoService()
        )

        let logCount = 50
        let threadCount = 10

        await withTaskGroup(of: Void.self) { group in
            for threadId in 0..<threadCount {
                group.addTask { @MainActor in
                    for i in 0..<logCount {
                        logr.info("Thread \(threadId) - Message \(i)", category: .test)
                    }
                }
            }
        }

        // Wait for all writes to complete
        try await Task.sleep(for: .seconds(2))

        // Verify logs in storage
        let storedCount = try await storage.count()
        let expectedTotal = logCount * threadCount

        #expect(storedCount == expectedTotal)
    }

    // MARK: - Stress Tests

    @MainActor
    @Test("Test high-volume concurrent logging with storage")
    func testHighVolumeConcurrentLoggingWithStorage() async throws {
        let storage = try createTestDatabase()
        let logr = LogR(
            storage: storage,
            cryptoService: createMockCryptoService()
        )

        let logCount = 100
        let threadCount = 20
        let expectedTotal = logCount * threadCount

        await withTaskGroup(of: Void.self) { group in
            for threadId in 0..<threadCount {
                group.addTask { @MainActor in
                    for i in 0..<logCount {
                        let level: LogLevel = [.debug, .info, .notice, .error, .fault].randomElement()!
                        let category: LogCategory = [.system, .network, .database, .ui, .test].randomElement()!
                        logr.log(
                            level: level,
                            message: "Thread \(threadId) - Message \(i) - \(UUID().uuidString)",
                            category: category
                        )
                    }
                }
            }
        }

        // Wait for all writes to complete
        try await Task.sleep(for: .seconds(3))

        // Verify all logs were stored
        let storedCount = try await storage.count()

        #expect(storedCount == expectedTotal)
    }

    @MainActor
    @Test("Test concurrent logging with mixed operations")
    func testConcurrentLoggingWithMixedOperations() async throws {
        let storage = try createTestDatabase()
        let logr = LogR(
            storage: storage,
            cryptoService: createMockCryptoService()
        )

        let logCount = 30

        await withTaskGroup(of: Void.self) { group in
            // Multiple logging threads
            for threadId in 0..<5 {
                group.addTask { @MainActor in
                    for i in 0..<logCount {
                        logr.info("Logger \(threadId) - Message \(i)", category: .test)
                    }
                }
            }
        }

        // Wait for all operations to complete
        try await Task.sleep(for: .seconds(2))

        // Verify logs were stored correctly
        let storedCount = try await storage.count()
        #expect(storedCount == logCount * 5)
    }

    // MARK: - Data Integrity Tests

    @MainActor
    @Test("Test concurrent logging preserves data integrity")
    func testConcurrentLoggingPreservesDataIntegrity() async throws {
        let storage = try createTestDatabase()
        let logr = LogR(
            storage: storage,
            cryptoService: createMockCryptoService()
        )

        let logCount = 50
        let threadCount = 10
        var expectedMessages: Set<String> = []

        // Generate unique messages
        for threadId in 0..<threadCount {
            for i in 0..<logCount {
                expectedMessages.insert("Thread \(threadId) - Message \(i)")
            }
        }

        await withTaskGroup(of: Void.self) { group in
            for threadId in 0..<threadCount {
                group.addTask {
                    for i in 0..<logCount {
                        await logr.info("Thread \(threadId) - Message \(i)", category: .test)
                    }
                }
            }
            await group.waitForAll()
        }

        // Wait for all writes to complete
        try await Task.sleep(for: .seconds(2))

        // Verify all unique messages were logged
        let actualMessages = Set(logr.recentLogs.map { $0.message })

        #expect(actualMessages.count == expectedMessages.count)
        #expect(actualMessages == expectedMessages)
    }

    @MainActor
    @Test("Test concurrent logging with different log levels")
    func testConcurrentLoggingWithDifferentLogLevels() async throws {
        let storage = try createTestDatabase()
        let logr = LogR(
            storage: storage,
            cryptoService: createMockCryptoService()
        )

        let logCount = 20
        let levels: [LogLevel] = [.debug, .info, .notice, .warning, .error, .fault]

        await withTaskGroup(of: Void.self) { group in
            for  level in levels {
                group.addTask { @MainActor in
                    for i in 0..<logCount {
                        logr.log(
                            level: level,
                            message: "Level \(level.rawValue) - Message \(i)",
                            category: .test
                        )
                    }
                }
            }
        }

        // Wait for all writes to complete
        try await Task.sleep(for: .seconds(2))

        // Verify all logs were stored
        let storedCount = try await storage.count()
        #expect(storedCount == logCount * levels.count)

        // Verify each level has the correct count
        for level in levels {
            let levelLogs = try logr.getLogs(levels: [level])
            #expect(levelLogs.count == logCount)
        }
    }

    @MainActor
    @Test("Test concurrent logging with different categories")
    func testConcurrentLoggingWithDifferentCategories() async throws {
        let storage = try createTestDatabase()
        let logr = LogR(
            storage: storage,
            cryptoService: createMockCryptoService()
        )

        let logCount = 20
        let categories: [LogCategory] = [.system, .network, .database, .ui, .authentication, .test]

        await withTaskGroup(of: Void.self) { group in
            for category in categories {
                group.addTask { @MainActor in
                    for i in 0..<logCount {
                        logr.info(
                            "Category \(category.rawValue) - Message \(i)",
                            category: category
                        )
                    }
                }
            }
        }

        // Wait for all writes to complete
        try await Task.sleep(for: .seconds(2))

        // Verify all logs were stored
        let storedCount = try await storage.count()
        #expect(storedCount == logCount * categories.count)

        // Verify each category has the correct count
        for category in categories {
            let categoryLogs = try logr.getLogs(categories: [category])
            #expect(categoryLogs.count == logCount)
        }
    }

    // MARK: - Edge Case Tests

    @MainActor
    @Test("Test concurrent logging with rapid bursts")
    func testConcurrentLoggingWithRapidBursts() async throws {
        let storage = try createTestDatabase()
        let logr = LogR(
            storage: storage,
            cryptoService: createMockCryptoService()
        )

        let burstSize = 100
        let burstCount = 10

        for burstId in 0..<burstCount {
            await withTaskGroup(of: Void.self) { group in
                for i in 0..<burstSize {
                    group.addTask { @MainActor in
                        logr.info("Burst \(burstId) - Message \(i)", category: .test)
                    }
                }
            }

            // Small delay between bursts
            try await Task.sleep(for: .milliseconds(100))
        }

        // Wait for all writes to complete
        try await Task.sleep(for: .seconds(2))

        // Verify all logs were stored
        let storedCount = try await storage.count()
        #expect(storedCount == burstSize * burstCount)
    }

    @MainActor
    @Test("Test concurrent logging with very long messages")
    func testConcurrentLoggingWithVeryLongMessages() async throws {
        let storage = try createTestDatabase()
        let logr = LogR(
            storage: storage,
            cryptoService: createMockCryptoService()
        )

        let threadCount = 10
        let longMessage = String(repeating: "A", count: 5000)

        await withTaskGroup(of: Void.self) { group in
            for threadId in 0..<threadCount {
                group.addTask { @MainActor in
                    logr.info("Thread \(threadId): \(longMessage)", category: .test)
                }
            }
        }

        // Wait for all writes to complete
        try await Task.sleep(for: .seconds(2))

        // Verify all logs were stored
        let storedCount = try await storage.count()
        #expect(storedCount == threadCount)
    }

    @MainActor
    @Test("Test concurrent logging with unicode messages")
    func testConcurrentLoggingWithUnicodeMessages() async throws {
        let storage = try createTestDatabase()
        let logr = LogR(
            storage: storage,
            cryptoService: createMockCryptoService()
        )

        let unicodeMessages = [
            "Hello 世界",
            "مرحبا بالعالم",
            "Привет мир",
            "שלום עולם",
            "こんにちは世界",
            "안녕하세요 세계",
            "Γειά σου κόσμε",
            "สวัสดีชาวโลก"
        ]

        await withTaskGroup(of: Void.self) { group in
            for (index, message) in unicodeMessages.enumerated() {
                group.addTask { @MainActor in
                    for i in 0..<5 {
                        logr.info("Message \(index)-\(i): \(message) 🌍", category: .test)
                    }
                }
            }
        }

        // Wait for all writes to complete
        try await Task.sleep(for: .seconds(2))

        // Verify all logs were stored
        let storedCount = try await storage.count()
        #expect(storedCount == unicodeMessages.count * 5)
    }

    // MARK: - Performance Tests

    @MainActor
    @Test("Test concurrent logging performance baseline")
    func testConcurrentLoggingPerformanceBaseline() async throws {
        let storage = try createTestDatabase()
        let logr = LogR(
            storage: storage,
            cryptoService: createMockCryptoService()
        )

        let logCount = 1000
        let startTime = Date()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<logCount {
                group.addTask { @MainActor in
                    logr.info("Performance test message \(i)", category: .test)
                }
            }
        }

        // Wait for all writes to complete
        try await Task.sleep(for: .seconds(3))

        let elapsed = Date().timeIntervalSince(startTime)

        // Verify all logs were stored
        let storedCount = try await storage.count()
        #expect(storedCount == logCount)

        // Log performance metrics (not a failure if slow, just informational)
        print("Logged \(logCount) messages in \(elapsed) seconds")
        print("Average: \(Double(logCount) / elapsed) logs/second")
    }

    // MARK: - Cleanup Tests

    @MainActor
    @Test("Test concurrent logging with periodic cleanup")
    func testConcurrentLoggingWithPeriodicCleanup() async throws {
        let storage = try createTestDatabase()
        let config = LogrConfiguration(
            maxLogEntries: 100,
            maxLogAge: 60, // 60 seconds
            cleanupInterval: 1 // 1 second
        )
        let logr = LogR(
            storage: storage,
            cryptoService: createMockCryptoService(),
            configuration: config
        )

        // Log many messages
        await withTaskGroup(of: Void.self) { group in
            for threadId in 0..<5 {
                group.addTask { @MainActor in
                    for i in 0..<50 {
                        logr.info("Thread \(threadId) - Message \(i)", category: .test)
                    }
                }
            }
        }

        // Recent logs should be limited by max entries
        #expect(logr.recentLogs.count <= config.maxLogEntries)
    }

    @MainActor
    @Test("Test storage integrity after many concurrent writes")
    func testStorageIntegrityAfterManyConcurrentWrites() async throws {
        let storage = try createTestDatabase()
        let cryptoService = createMockCryptoService()
        let logr = LogR(
            storage: storage,
            cryptoService: cryptoService
        )

        let totalLogs = 500

        // Write logs concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<totalLogs {
                group.addTask { @MainActor in
                    logr.info("Test message \(i)", category: .test)
                }
            }
        }

        // Wait for all writes to complete
        try await Task.sleep(for: .seconds(3))

        // Fetch and verify storage
        let encryptedEntries = try await storage.fetchEntries()
        #expect(encryptedEntries.count == totalLogs)

        // Verify each entry can be decrypted
        var successfulDecryptions = 0
        for encryptedEntry in encryptedEntries {
            do {
                let _: LogEntry = try cryptoService.symmetricDecrypt(encryptedData: encryptedEntry.data)
                successfulDecryptions += 1
            } catch {
                Issue.record("Failed to decrypt entry: \(error)")
            }
        }

        #expect(successfulDecryptions == totalLogs)
    }
}
