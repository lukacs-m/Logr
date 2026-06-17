import Testing
@testable import Logr
import Foundation
import Collections

final class MockKeychainService: @unchecked Sendable, KeychainStore {
    var storage: [String: Data] = [:]
    
    func set(_ data: Data, forKey key: String) throws{
        storage[key] = data
    }
    
    func data(forKey key: String) throws -> Data? {
        guard let data = storage[key] else {
            return nil
        }
        return data
    }
    
    func remove(forKey key: String) throws {
        storage.removeValue(forKey: key)
    }
}

/// Counts how many times its message factory is evaluated. Used to prove that
/// the logging `@autoclosure` is only invoked when the level is actually enabled.
@MainActor
final class EvaluationCounter {
    private(set) var count = 0
    func track() -> String {
        count += 1
        return "tracked-message"
    }
}

@MainActor
@Suite("LogR Core Functionality")
struct LogrTests {

    let cryptoService = try! LoggerCryptoService(store: MockKeychainService())
    // MARK: - Basic Logging Tests

    @Test("Test basic debug logging")
    func testDebugLogging() async throws {
        let logr = LogR(cryptoService: cryptoService)

        logr.debug("Debug message", category: .debug)

        #expect(logr.recentLogs.count == 1)
        #expect(logr.recentLogs.first?.level == .debug)
        #expect(logr.recentLogs.first?.message == "Debug message")
        #expect(logr.recentLogs.first?.category == .debug)
    }

    @Test("Test basic info logging")
    func testInfoLogging() async throws {
        let logr =  LogR(cryptoService: cryptoService)

        logr.info("Info message", category: .system)

        #expect(logr.recentLogs.count == 1)
        #expect(logr.recentLogs.first?.level == .info)
        #expect(logr.recentLogs.first?.message == "Info message")
    }

    @Test("Test basic notice logging")
    func testNoticeLogging() async throws {
        let logr =  LogR(cryptoService: cryptoService)

        logr.notice("Notice message", category: .system)

        #expect(logr.recentLogs.count == 1)
        #expect(logr.recentLogs.first?.level == .notice)
        #expect(logr.recentLogs.first?.message == "Notice message")
    }

    @Test("Test basic error logging")
    func testErrorLogging() async throws {
        let logr =  LogR(cryptoService: cryptoService)

        logr.error("Error message", category: .system)

        #expect(logr.recentLogs.count == 1)
        #expect(logr.recentLogs.first?.level == .error)
        #expect(logr.recentLogs.first?.message == "Error message")
    }

    @Test("Test basic fault logging")
    func testFaultLogging() async throws {
        let logr =  LogR(cryptoService: cryptoService)

        logr.fault("Fault message", category: .system)

        #expect(logr.recentLogs.count == 1)
        #expect(logr.recentLogs.first?.level == .fault)
        #expect(logr.recentLogs.first?.message == "Fault message")
    }

    @Test("Test all log levels")
    func testAllLogLevels() async throws {
        let logr =  LogR(cryptoService: cryptoService)

        logr.debug("Debug")
        logr.info("Info")
        logr.notice("Notice")
        logr.error("Error")
        logr.fault("Fault")

        // Publish the coalesced buffer before inspecting `recentLogs` directly.
        await logr.flush()

        #expect(logr.recentLogs.count == 5)

        // Verify logs are in reverse chronological order (newest first)
        #expect(logr.recentLogs[0].message == "Fault")
        #expect(logr.recentLogs[1].message == "Error")
        #expect(logr.recentLogs[2].message == "Notice")
        #expect(logr.recentLogs[3].message == "Info")
        #expect(logr.recentLogs[4].message == "Debug")
    }

    // MARK: - Existential read consistency (A1 regression)

    @Test("Reads through the LogRService existential reflect a burst with no await")
    func testExistentialReadsReflectBurstImmediately() async throws {
        // LogrUI and consumers hold the service as `any LogRService`. A burst of logs
        // within the coalescing window must be visible to every read API immediately —
        // the synchronous reads without any intervening `await`, through the existential,
        // not just the concrete type.
        let service: any LogRService = LogR(cryptoService: cryptoService)

        service.info("a")
        service.info("b")
        service.info("c")

        // Synchronous reads see the burst with no await — the core source-of-truth guarantee.
        #expect(service.recentLogs.count == 3)
        #expect(try service.getLogs().count == 3)
        #expect(try service.getLogs(limit: 2).count == 2)

        // Export/statistics now run off the main actor (so they're `async`), but still reflect the
        // burst — the async is about *where* the work runs, not whether the data is current.
        let exported = try await service.exportLogs()
        #expect(!exported.isEmpty)
        #expect(await service.logStatistics().totalCount == 3)
    }

    // MARK: - Lazy Evaluation Tests

    @Test("Disabled log level does not evaluate the message autoclosure")
    func testDisabledLevelSkipsMessageEvaluation() async throws {
        let config = LogrConfiguration(enabledLevels: [.error, .fault])
        let logr = LogR(cryptoService: cryptoService, configuration: config)
        let counter = EvaluationCounter()

        // `.debug` is not enabled — the message must never be built.
        logr.debug(counter.track())
        #expect(counter.count == 0)

        // `.error` is enabled — the message is built exactly once.
        logr.error(counter.track())
        #expect(counter.count == 1)
    }

    @Test("Category-level override below threshold skips message evaluation")
    func testCategoryOverrideSkipsMessageEvaluation() async throws {
        let config = LogrConfiguration(enabledLevels: Set(LogLevel.allCases),
                                       categoryLevelOverrides: [.network: .error])
        let logr = LogR(cryptoService: cryptoService, configuration: config)
        let counter = EvaluationCounter()

        // `.network` only logs `.error`+ — a `.debug` to `.network` must not evaluate.
        logr.debug(counter.track(), category: .network)
        #expect(counter.count == 0)
    }

    // MARK: - Cleanup Tests

    private func agedEntry(_ message: String, ageSeconds: TimeInterval, now: Date) -> LogEntry {
        LogEntry(timestamp: now.addingTimeInterval(-ageSeconds),
                 level: .info,
                 category: .system,
                 subsystem: "test",
                 message: message)
    }

    @Test("Expired entries are trimmed from the tail and fresh entries kept, in order")
    func testTrimExpiredEntries() async throws {
        let now = Date()
        let cutoff = now.addingTimeInterval(-60) // entries older than 60s expire
        // Newest-first ordering: fresh at the front, oldest at the back.
        var deque: Deque<LogEntry> = [
            agedEntry("fresh-2", ageSeconds: 5, now: now),
            agedEntry("fresh-1", ageSeconds: 30, now: now),
            agedEntry("old-1", ageSeconds: 120, now: now),
            agedEntry("old-2", ageSeconds: 600, now: now)
        ]

        LogR.trimExpiredEntries(&deque, olderThan: cutoff)

        #expect(deque.map(\.message) == ["fresh-2", "fresh-1"])
    }

    @Test("Trimming is a no-op when nothing has expired")
    func testTrimExpiredNoOp() async throws {
        let now = Date()
        let cutoff = now.addingTimeInterval(-3600)
        var deque: Deque<LogEntry> = [
            agedEntry("a", ageSeconds: 1, now: now),
            agedEntry("b", ageSeconds: 100, now: now)
        ]

        LogR.trimExpiredEntries(&deque, olderThan: cutoff)

        #expect(deque.count == 2)
        #expect(deque.map(\.message) == ["a", "b"])
    }

    // MARK: - Load Merge Tests

    @Test("Loaded history is merged newest-first, after any logs captured during launch")
    func testMergeLoadedHistoryOrder() async throws {
        let now = Date()
        // As returned by fetchEntries(limit:): oldest-first.
        let historical = [
            agedEntry("h1", ageSeconds: 50, now: now),
            agedEntry("h2", ageSeconds: 40, now: now),
            agedEntry("h3", ageSeconds: 30, now: now)
        ]
        // Live logs captured during launch: newest-first, newer than the history.
        var current: Deque<LogEntry> = [
            agedEntry("live2", ageSeconds: 1, now: now),
            agedEntry("live1", ageSeconds: 2, now: now)
        ]

        LogR.mergeLoaded(historical, into: &current, cap: 100)

        #expect(current.map(\.message) == ["live2", "live1", "h3", "h2", "h1"])
    }

    @Test("Merging loaded history drops the oldest beyond the cap")
    func testMergeLoadedRespectsCap() async throws {
        let now = Date()
        // oldest-first: h1 (oldest) … h6 (newest)
        let historical = (1 ... 6).map { agedEntry("h\($0)", ageSeconds: Double(60 - $0), now: now) }
        var current: Deque<LogEntry> = []

        LogR.mergeLoaded(historical, into: &current, cap: 3)

        #expect(current.map(\.message) == ["h6", "h5", "h4"])
    }

    // MARK: - Configuration Tests

    @Test("LogrConfiguration decodes JSON missing the 1.2.0 fields by falling back to defaults")
    func testConfigDecodesJSONWithoutNewFields() throws {
        // Round-trip the default config, then strip the fields added in 1.2.0 to simulate a config
        // encoded by an earlier release. Decoding must succeed (defaults applied), not throw.
        let encoded = try JSONEncoder().encode(LogrConfiguration.default)
        var object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "coalesceWindowMillis")
        object.removeValue(forKey: "mirrorToOSLog")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let config = try JSONDecoder().decode(LogrConfiguration.self, from: legacy)

        #expect(config.coalesceWindowMillis == LogrConfiguration.default.coalesceWindowMillis)
        #expect(config.mirrorToOSLog == LogrConfiguration.default.mirrorToOSLog)
        #expect(config.maxLogEntries == LogrConfiguration.default.maxLogEntries)
        #expect(config.subsystem == LogrConfiguration.default.subsystem)
    }

    @Test("LogrConfiguration round-trips through Codable")
    func testConfigCodableRoundTrip() throws {
        let original = LogrConfiguration(maxLogEntries: 42,
                                         enabledLevels: [.warning, .error],
                                         subsystem: "com.test.roundtrip",
                                         logVerbosity: .normal,
                                         coalesceWindowMillis: 250,
                                         mirrorToOSLog: false)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LogrConfiguration.self, from: data)

        #expect(decoded.maxLogEntries == 42)
        #expect(decoded.enabledLevels == [.warning, .error])
        #expect(decoded.subsystem == "com.test.roundtrip")
        #expect(decoded.logVerbosity == .normal)
        #expect(decoded.coalesceWindowMillis == 250)
        #expect(decoded.mirrorToOSLog == false)
    }

    @Test("Test custom configuration max log entries")
    func testMaxLogEntriesConfiguration() async throws {
        let config = LogrConfiguration(maxLogEntries: 3)
        let logr = LogR(cryptoService: cryptoService,configuration: config)

        logr.info("Message 1")
        logr.info("Message 2")
        logr.info("Message 3")
        logr.info("Message 4")

        await logr.flush()

        // Should only keep the 3 most recent logs
        #expect(logr.recentLogs.count == 3)
        #expect(logr.recentLogs[0].message == "Message 4")
        #expect(logr.recentLogs[1].message == "Message 3")
        #expect(logr.recentLogs[2].message == "Message 2")
    }

    @Test("Test enabled log levels configuration")
    func testEnabledLogLevelsConfiguration() async throws {
        // Only enable error and fault levels
        let config = LogrConfiguration(enabledLevels: [.error, .fault])
        let logr = LogR(cryptoService: cryptoService, configuration: config)

        logr.debug("Debug message")
        logr.info("Info message")
        logr.notice("Notice message")
        logr.error("Error message")
        logr.fault("Fault message")

        await logr.flush()

        // Should only have error and fault logs
        #expect(logr.recentLogs.count == 2)
        #expect(logr.recentLogs[0].level == .fault)
        #expect(logr.recentLogs[1].level == .error)
    }

    @Test("Test verbose logging configuration")
    func testVerboseLoggingConfiguration() async throws {
        let config = LogrConfiguration(logVerbosity: .verbose)
        let logr = LogR(cryptoService: cryptoService, configuration: config)

        logr.info("Test message")

        #expect(logr.recentLogs.count == 1)
        #expect(logr.recentLogs.first?.message == "Test message")
    }

    @Test("Test normal logging configuration")
    func testNormalLoggingConfiguration() async throws {
        let config = LogrConfiguration(logVerbosity: .normal)
        let logr = LogR(cryptoService: cryptoService, configuration: config)

        logr.info("Test message")

        #expect(logr.recentLogs.count == 1)
        #expect(logr.recentLogs.first?.message == "Test message")
    }

    // MARK: - Log Filtering Tests

    @Test("Test filtering by log level")
    func testFilteringByLogLevel() async throws {
        let logr = LogR(cryptoService: cryptoService)

        logr.debug("Debug 1")
        logr.info("Info 1")
        logr.error("Error 1")
        logr.debug("Debug 2")
        logr.error("Error 2")

        let errorLogs = try logr.getLogs(levels: [.error])

        #expect(errorLogs.count == 2)
        #expect(errorLogs.allSatisfy { $0.level == .error })
    }

    @Test("Test filtering by category")
    func testFilteringByCategory() async throws {
        let logr = LogR(cryptoService: cryptoService)

        logr.info("System message", category: .system)
        logr.info("Network message", category: .network)
        logr.info("Database message", category: .database)
        logr.info("Another system message", category: .system)

        let systemLogs = try logr.getLogs(categories: [.system])

        #expect(systemLogs.count == 2)
        #expect(systemLogs.allSatisfy { $0.category == .system })
    }

    @Test("Test filtering by multiple categories")
    func testFilteringByMultipleCategories() async throws {
        let logr = LogR(cryptoService: cryptoService)

        logr.info("System message", category: .system)
        logr.info("Network message", category: .network)
        logr.info("Database message", category: .database)
        logr.info("UI message", category: .ui)

        let filteredLogs = try logr.getLogs(categories: [.system, .network])

        #expect(filteredLogs.count == 2)
        #expect(filteredLogs.allSatisfy { $0.category == .system || $0.category == .network })
    }

    @Test("Test filtering by date range")
    func testFilteringByDateRange() async throws {
        let logr = LogR(cryptoService: cryptoService)

        let now = Date()
        let oneHourAgo = now.addingTimeInterval(-3600)

        // Create an old log (if your LogR supports setting timestamps)
        // If not, you may need to mock the date or add a test-only initializer
        logr.log(level: .info, message: "Old message", category: .system)
        logr.log(level: .info, message: "Recent message", category: .system)

        // Filter logs from now (should get all logs just created)
        let recentLogs = try logr.getLogs(from: oneHourAgo)

        // Since both logs were just created (within the last second), both should be included
        #expect(recentLogs.count == 2)
        
        // If you want to test actual filtering, you need to either:
        // 1. Mock the date when logs are created
        // 2. Add a way to set custom timestamps in your LogR for testing
        // 3. Filter with a future date to exclude logs
        let futureLogs = try logr.getLogs(from: now.addingTimeInterval(60))
        #expect(futureLogs.count == 0) // No logs from the future
    }

    @Test("Test filtering with limit")
    func testFilteringWithLimit() async throws {
        let logr = LogR(cryptoService: cryptoService)

        for i in 1...10 {
            logr.info("Message \(i)")
        }

        let limitedLogs = try logr.getLogs(limit: 5)

        #expect(limitedLogs.count == 5)
        // Should get the 5 most recent logs
        #expect(limitedLogs[0].message == "Message 10")
        #expect(limitedLogs[4].message == "Message 6")
    }

    @Test("Test filtering by subsystem")
    func testFilteringBySubsystem() async throws {
        let config1 = LogrConfiguration(subsystem: "com.test.app1")
        let logr = LogR(cryptoService: cryptoService, configuration: config1)

        logr.info("Message from app1")

        let logs = try logr.getLogs(subsystems: ["com.test.app1"])

        #expect(logs.count == 1)
        #expect(logs.first?.subsystem == "com.test.app1")
    }

    @Test("Test combined filtering")
    func testCombinedFiltering() async throws {
        let logr = LogR(cryptoService: cryptoService)

        logr.debug("Debug system", category: .system)
        logr.info("Info system", category: .system)
        logr.error("Error system", category: .system)
        logr.info("Info network", category: .network)
        logr.error("Error network", category: .network)

        let filteredLogs = try logr.getLogs(
            levels: [.info, .error],
            categories: [.system]
        )

        #expect(filteredLogs.count == 2)
        #expect(filteredLogs.allSatisfy { $0.category == .system && ($0.level == .info || $0.level == .error) })
    }

    // MARK: - Export Tests

    @Test("Test export logs as JSON")
    func testExportLogsAsJSON() async throws {
        let logr = LogR(cryptoService: cryptoService)

        logr.info("Test message 1", category: .system)
        logr.error("Test message 2", category: .network)

        let jsonData = try await logr.exportLogs(format: .json)

        #expect(!jsonData.isEmpty)

        // Verify it's valid JSON
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let logs = try decoder.decode([LogEntry].self, from: jsonData)

        #expect(logs.count == 2)
    }

    @Test("Test export logs as CSV")
    func testExportLogsAsCSV() async throws {
        let logr = LogR(cryptoService: cryptoService)

        logr.info("Test message 1", category: .system)
        logr.error("Test message 2", category: .network)

        let csvData = try await logr.exportLogs(format: .csv)

        #expect(!csvData.isEmpty)

        // Verify CSV format
        let csvString = String(data: csvData, encoding: .utf8)
        #expect(csvString != nil)
        #expect(csvString!.contains("Timestamp,Level,Category,Subsystem,Message,File,Function,Line"))
        #expect(csvString!.contains("Test message 1"))
        #expect(csvString!.contains("Test message 2"))
    }

    @Test("Test export logs as TXT")
    func testExportLogsAsTXT() async throws {
        let logr = LogR(cryptoService: cryptoService)

        logr.info("Test message 1", category: .system)
        logr.error("Test message 2", category: .network)

        let txtData = try await logr.exportLogs(format: .txt)

        #expect(!txtData.isEmpty)

        let txtString = String(data: txtData, encoding: .utf8)
        #expect(txtString != nil)
        #expect(txtString!.contains("Test message 1"))
        #expect(txtString!.contains("Test message 2"))
        #expect(txtString!.contains("INFO"))
        #expect(txtString!.contains("ERROR"))
    }

    @Test("Test export with special characters in CSV")
    func testExportWithSpecialCharactersInCSV() async throws {
        let logr = LogR(cryptoService: cryptoService)

        logr.info("Message with \"quotes\"", category: .system)
        logr.info("Message with, commas", category: .system)

        let csvData = try await logr.exportLogs(format: .csv)
        let csvString = String(data: csvData, encoding: .utf8)

        #expect(csvString != nil)
        // CSV should properly escape quotes
        #expect(csvString!.contains("\"\""))
    }

    // MARK: - Clear Logs Tests

    @Test("Test clear logs")
    func testClearLogs() async throws {
        let logr = LogR(cryptoService: cryptoService)

        logr.info("Message 1")
        logr.info("Message 2")
        logr.info("Message 3")

        await logr.flush()

        #expect(logr.recentLogs.count == 3)

        try await logr.clearLogs()

        #expect(logr.recentLogs.isEmpty)
    }

    // MARK: - Category Tests

    @Test("Test logging with different categories")
    func testLoggingWithDifferentCategories() async throws {
        let logr = LogR(cryptoService: cryptoService)

        logr.info("System message", category: .system)
        logr.info("Network message", category: .network)
        logr.info("Database message", category: .database)
        logr.info("UI message", category: .ui)
        logr.info("Custom message", category: .custom("MyCategory"))

        await logr.flush()

        #expect(logr.recentLogs.count == 5)

        let categories = logr.recentLogs.map { $0.category }
        #expect(categories.contains(.system))
        #expect(categories.contains(.network))
        #expect(categories.contains(.database))
        #expect(categories.contains(.ui))
        #expect(categories.contains(.custom("MyCategory")))
    }

    // MARK: - Empty State Tests

    @Test("Test filtering on empty logs")
    func testFilteringOnEmptyLogs() async throws {
        let logr = LogR(cryptoService: cryptoService)

        let logs = try logr.getLogs(levels: [.error])

        #expect(logs.isEmpty)
    }

    @Test("Test export on empty logs returns empty data (not nil)")
    func testExportOnEmptyLogs() async throws {
        let logr = LogR(cryptoService: cryptoService)

        // Empty cache now yields empty `Data` rather than `nil`, so callers can distinguish
        // "no logs" from a genuine encoding failure (which throws).
        let jsonData = try await logr.exportLogs(format: .json)

        #expect(jsonData.isEmpty)
    }

    // MARK: - Metadata Tests

    @Test("Test log entry metadata")
    func testLogEntryMetadata() async throws {
        let logr = LogR(cryptoService: cryptoService)

        logr.info("Test message", category: .system)

        let log = logr.recentLogs.first!

        #expect(!log.id.isEmpty)
        #expect(log.timestamp <= Date())
        #expect(!log.file.isEmpty)
        #expect(!log.function.isEmpty)
        #expect(log.line > 0)
    }

    // MARK: - Edge Cases

    @Test("Test logging with empty message")
    func testLoggingWithEmptyMessage() async throws {
        let logr = LogR(cryptoService: cryptoService)

        logr.info("", category: .system)

        #expect(logr.recentLogs.count == 1)
        #expect(logr.recentLogs.first?.message == "")
    }

    @Test("Test logging with very long message")
    func testLoggingWithVeryLongMessage() async throws {
        let logr = LogR(cryptoService: cryptoService)
        let longMessage = String(repeating: "A", count: 10000)

        logr.info(longMessage, category: .system)

        #expect(logr.recentLogs.count == 1)
        #expect(logr.recentLogs.first?.message.count == 10000)
    }

    @Test("Test logging with unicode characters")
    func testLoggingWithUnicodeCharacters() async throws {
        let logr = LogR(cryptoService: cryptoService)

        logr.info("Hello 世界 🌍 مرحبا", category: .system)

        #expect(logr.recentLogs.count == 1)
        #expect(logr.recentLogs.first?.message == "Hello 世界 🌍 مرحبا")
    }

    @Test("Test multiple rapid logs")
    func testMultipleRapidLogs() async throws {
        let logr = LogR(cryptoService: cryptoService)

        for i in 1...100 {
            logr.info("Message \(i)")
        }

        await logr.flush()

        #expect(logr.recentLogs.count == 100)
    }

    @Test("Test log entry properties")
    func testLogEntryProperties() async throws {
        let config = LogrConfiguration(subsystem: "com.test.myapp")
        let logr = LogR(cryptoService: cryptoService, configuration: config)

        logr.error("Error occurred", category: .network)

        let entry = logr.recentLogs.first!

        #expect(entry.level == .error)
        #expect(entry.category == .network)
        #expect(entry.subsystem == "com.test.myapp")
        #expect(entry.message == "Error occurred")
        #expect(!entry.id.isEmpty)
        #expect(entry.timestamp <= Date())
    }
}
