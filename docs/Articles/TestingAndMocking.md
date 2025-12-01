---
layout: default
title: Testing and Mocking
nav_order: 8
parent: Logr Documentation
---

# Testing and Mocking

Learn how to test your logging code and use MockLogR for development and testing.

[← Back to Documentation](../docs/index.md)

## Overview

Logr provides comprehensive testing support through `MockLogR`, a full-featured mock implementation that works seamlessly in SwiftUI previews and unit tests.

## MockLogR

The `MockLogR` class implements `LogRService` with in-memory storage and pre-populated sample data.

### Features

- Full `LogRService` protocol compliance
- Pre-populated with realistic sample logs
- In-memory storage (no disk I/O)
- All querying and filtering capabilities
- Export functionality
- Perfect for SwiftUI previews
- Ideal for unit testing

### Basic Usage

```swift
import Logr

// Create a mock logger
let mock = MockLogR()

// Use it like a real logger
mock.info("Test message", category: .network)
mock.error("Test error", category: .database)

// Access logs
print("Total logs: \(mock.recentLogs.count)")
```

## SwiftUI Previews

Use `MockLogR` in SwiftUI previews for instant feedback without running the app.

### Basic Preview

```swift
#Preview {
    NavigationStack {
        LogViewer()
    }
    .environment(\.logService, MockLogR())
}
```

### Custom Preview Data

```swift
#Preview("Error Logs") {
    let mock = MockLogR()

    // Clear default logs
    Task { try? await mock.clearLogs() }

    // Add specific test logs
    mock.error("Network timeout", category: .network)
    mock.error("Database connection failed", category: .database)
    mock.fault("Critical system error", category: .system)

    return NavigationStack {
        LogViewer()
    }
    .environment(\.logService, mock)
}
```

### Multiple Preview Scenarios

```swift
#Preview("Empty State") {
    let mock = MockLogR()
    Task { try? await mock.clearLogs() }

    return LogViewer()
        .environment(\.logService, mock)
}

#Preview("With Logs") {
    LogViewer()
        .environment(\.logService, MockLogR())
}

#Preview("Many Errors") {
    let mock = MockLogR()

    for i in 1...20 {
        mock.error("Error \(i)", category: .network)
    }

    return LogViewer()
        .environment(\.logService, mock)
}
```

### Testing Custom Views

```swift
struct MyLogView: View {
    @Environment(\.logService) private var logger

    var body: some View {
        List(logger.recentLogs.filter { $0.level == .error }) { log in
            Text(log.message)
        }
    }
}

#Preview {
    let mock = MockLogR()
    mock.error("Test error 1", category: .network)
    mock.error("Test error 2", category: .database)

    return MyLogView()
        .logRService(mock)
}
```

## Unit Testing

Use `MockLogR` to test logging behavior in your code.

### Setup

```swift
import XCTest
import Logr

class MyViewModelTests: XCTestCase {
    var mockLogger: MockLogR!
    var viewModel: MyViewModel!

    override func setUp() {
        super.setUp()
        mockLogger = MockLogR()
        viewModel = MyViewModel(logger: mockLogger)
    }

    override func tearDown() {
        mockLogger = nil
        viewModel = nil
        super.tearDown()
    }
}
```

### Testing Log Output

```swift
func testLoggingOnSuccess() async throws {
    // Given
    await viewModel.performAction()

    // Then
    XCTAssertFalse(mockLogger.recentLogs.isEmpty)

    let infoLogs = mockLogger.recentLogs.filter { $0.level == .info }
    XCTAssertEqual(infoLogs.count, 1)
    XCTAssertEqual(infoLogs.first?.message, "Action completed successfully")
    XCTAssertEqual(infoLogs.first?.category, .user)
}

func testLoggingOnError() async throws {
    // Given
    viewModel.shouldFail = true

    // When
    await viewModel.performAction()

    // Then
    let errorLogs = mockLogger.recentLogs.filter { $0.level == .error }
    XCTAssertGreaterThan(errorLogs.count, 0)
    XCTAssertTrue(errorLogs.first?.message.contains("failed") ?? false)
}
```

### Testing Log Levels

```swift
func testDebugLogsDisabledInProduction() {
    // Given
    let productionLogger = LogR(
        configuration: LogrConfiguration(
            enabledLevels: [.info, .warning, .error, .fault]
        )
    )

    // When
    productionLogger.debug("Debug message", category: .debug)

    // Then
    let debugLogs = productionLogger.recentLogs.filter { $0.level == .debug }
    XCTAssertEqual(debugLogs.count, 0, "Debug logs should be disabled in production")
}
```

### Testing Categories

```swift
func testNetworkLogsUseCorrectCategory() async {
    // When
    await viewModel.fetchData()

    // Then
    let networkLogs = mockLogger.recentLogs.filter {
        $0.category == .network || $0.category == .api
    }

    XCTAssertGreaterThan(networkLogs.count, 0, "Network operations should log to network categories")
}
```

### Testing Log Queries

```swift
func testGetLogsByLevel() throws {
    // Given
    mockLogger.info("Info message", category: .system)
    mockLogger.error("Error message", category: .system)
    mockLogger.fault("Fault message", category: .system)

    // When
    let errorLogs = try mockLogger.getLogs(levels: [.error, .fault])

    // Then
    XCTAssertEqual(errorLogs.count, 2)
    XCTAssertTrue(errorLogs.allSatisfy { $0.level == .error || $0.level == .fault })
}

func testGetLogsByCategory() throws {
    // Given
    mockLogger.info("Network log", category: .network)
    mockLogger.info("UI log", category: .ui)
    mockLogger.info("Database log", category: .database)

    // When
    let networkLogs = try mockLogger.getLogs(categories: [.network])

    // Then
    XCTAssertEqual(networkLogs.count, 1)
    XCTAssertEqual(networkLogs.first?.category, .network)
}

func testGetLogsByDateRange() throws {
    // Given
    let now = Date()
    let oneHourAgo = now.addingTimeInterval(-3600)
    let twoHoursAgo = now.addingTimeInterval(-7200)

    // When
    let recentLogs = try mockLogger.getLogs(
        from: oneHourAgo,
        to: now
    )

    // Then
    XCTAssertTrue(recentLogs.allSatisfy { log in
        log.timestamp >= oneHourAgo && log.timestamp <= now
    })
}
```

### Testing Export

```swift
func testExportLogsAsJSON() {
    // Given
    mockLogger.info("Test log", category: .system)

    // When
    let jsonData = mockLogger.exportLogs(format: .json)

    // Then
    XCTAssertNotNil(jsonData)

    // Verify JSON is valid
    let decoder = JSONDecoder()
    XCTAssertNoThrow(try decoder.decode([LogEntry].self, from: jsonData!))
}

func testExportLogsAsCSV() {
    // When
    let csvData = mockLogger.exportLogs(format: .csv)

    // Then
    XCTAssertNotNil(csvData)

    let csvString = String(data: csvData!, encoding: .utf8)
    XCTAssertTrue(csvString?.contains("timestamp") ?? false)
    XCTAssertTrue(csvString?.contains("level") ?? false)
    XCTAssertTrue(csvString?.contains("message") ?? false)
}
```

### Testing Clear Logs

```swift
func testClearLogs() async throws {
    // Given
    mockLogger.info("Log 1", category: .system)
    mockLogger.info("Log 2", category: .system)
    XCTAssertFalse(mockLogger.recentLogs.isEmpty)

    // When
    try await mockLogger.clearLogs()

    // Then
    XCTAssertTrue(mockLogger.recentLogs.isEmpty)
}
```

## Integration Testing

Test the full Logr system with actual storage.

### Setup Test Storage

```swift
class LogRIntegrationTests: XCTestCase {
    var logger: LogR!
    var testDirectory: URL!

    override func setUp() {
        super.setUp()

        // Create temporary directory
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        try! FileManager.default.createDirectory(
            at: testDirectory,
            withIntermediateDirectories: true
        )

        // Create logger with test storage
        let storage = SQLiteStorage(
            databaseURL: testDirectory.appendingPathComponent("test.db")
        )

        logger = LogR(storage: storage)
    }

    override func tearDown() {
        // Clean up test directory
        try? FileManager.default.removeItem(at: testDirectory)

        logger = nil
        testDirectory = nil

        super.tearDown()
    }
}
```

### Testing Persistence

```swift
func testLogsPersistAcrossInstances() async throws {
    // Given
    logger.info("Persistent log", category: .system)
    await logger.flush()

    // When - create new logger with same storage
    let storage = SQLiteStorage(
        databaseURL: testDirectory.appendingPathComponent("test.db")
    )
    let newLogger = LogR(storage: storage)

    // Wait for initialization
    try await Task.sleep(for: .seconds(1))

    // Then
    XCTAssertFalse(newLogger.recentLogs.isEmpty)
    XCTAssertTrue(newLogger.recentLogs.contains { $0.message == "Persistent log" })
}
```

### Testing Cleanup

```swift
func testAutomaticCleanup() async throws {
    // Given - configure short retention
    let config = LogrConfiguration(
        maxLogAge: 1, // 1 second
        cleanupInterval: 2 // 2 seconds
    )

    let logger = LogR(
        storage: SQLiteStorage(),
        configuration: config
    )

    logger.info("Old log", category: .system)

    // When - wait for cleanup
    try await Task.sleep(for: .seconds(3))

    // Then
    XCTAssertTrue(logger.recentLogs.isEmpty, "Old logs should be cleaned up")
}
```

### Testing Encryption

```swift
func testLogsAreEncrypted() async throws {
    // Given
    let storage = SQLiteStorage(
        databaseURL: testDirectory.appendingPathComponent("test.db")
    )
    let logger = LogR(storage: storage)

    logger.info("Secret message", category: .system)
    await logger.flush()

    // When - read raw database
    let dbData = try Data(contentsOf: testDirectory.appendingPathComponent("test.db"))
    let dbString = String(data: dbData, encoding: .utf8) ?? ""

    // Then - plaintext message should not appear in database
    XCTAssertFalse(dbString.contains("Secret message"), "Logs should be encrypted")
}
```

## Testing Custom Implementations

### Testing Custom Storage

```swift
class CustomStorageTests: XCTestCase {
    var storage: MyCustomStorage!

    func testStoreAndFetch() async throws {
        // Given
        storage = MyCustomStorage()

        let entry = EncryptedLogEntry(
            id: UUID().uuidString,
            timestamp: Date(),
            data: Data("test".utf8)
        )

        // When
        try await storage.store(entry)
        let fetched = try await storage.fetchEntries()

        // Then
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, entry.id)
    }

    func testDeleteOldEntries() async throws {
        // Test deletion logic
    }

    func testClear() async throws {
        // Test clear functionality
    }
}
```

### Testing Custom Crypto

```swift
class CustomCryptoTests: XCTestCase {
    var crypto: MyCustomCrypto!

    func testEncryptDecrypt() throws {
        // Given
        crypto = MyCustomCrypto()
        let original = LogEntry(
            level: .info,
            category: .system,
            subsystem: "test",
            message: "Test message"
        )

        // When
        let encrypted = try crypto.symmetricEncrypt(object: original)
        let decrypted: LogEntry = try crypto.symmetricDecrypt(encryptedData: encrypted)

        // Then
        XCTAssertEqual(decrypted.message, original.message)
        XCTAssertEqual(decrypted.level, original.level)
    }
}
```

## Test Utilities

### Helper Extensions

```swift
extension MockLogR {
    /// Clears all logs synchronously for testing
    func clearLogsSync() {
        Task {
            try? await clearLogs()
        }
    }

    /// Adds multiple test logs
    func addTestLogs(count: Int) {
        for i in 1...count {
            info("Test log \(i)", category: .test)
        }
    }

    /// Gets logs matching a predicate
    func getLogs(where predicate: (LogEntry) -> Bool) -> [LogEntry] {
        recentLogs.filter(predicate)
    }
}
```

### Test Fixtures

```swift
extension LogEntry {
    static func fixture(
        level: LogLevel = .info,
        category: LogCategory = .system,
        message: String = "Test message"
    ) -> LogEntry {
        LogEntry(
            level: level,
            category: category,
            subsystem: "test",
            message: message
        )
    }
}

// Usage in tests
func testSomething() {
    let log = LogEntry.fixture(level: .error, message: "Test error")
    // Test with fixture
}
```

## Performance Testing

### Measure Logging Performance

```swift
func testLoggingPerformance() {
    let logger = MockLogR()

    measure {
        for _ in 1...1_000 {
            logger.info("Performance test", category: .performance)
        }
    }
}
```

### Measure Query Performance

```swift
func testQueryPerformance() {
    let logger = MockLogR()

    // Add many logs
    for i in 1...10_000 {
        logger.info("Log \(i)", category: .system)
    }

    measure {
        _ = try? logger.getLogs(levels: [.info])
    }
}
```

## Best Practices

### 1. Use MockLogR for UI Tests

```swift
// ✅ Good - fast, predictable
#Preview {
    ContentView()
        .environment(\.logService, MockLogR())
}

// ❌ Bad - slow, file I/O in previews
#Preview {
    ContentView()
        .environment(\.logService, LogR(storage: SQLiteStorage()))
}
```

### 2. Clean Up Between Tests

```swift
override func setUp() {
    super.setUp()
    mockLogger = MockLogR()
}

override func tearDown() {
    Task {
        try? await mockLogger.clearLogs()
    }
    mockLogger = nil
    super.tearDown()
}
```

### 3. Test Edge Cases

```swift
func testLoggingEmptyMessage() {
    mockLogger.info("", category: .system)
    XCTAssertFalse(mockLogger.recentLogs.isEmpty)
}

func testLoggingVeryLongMessage() {
    let longMessage = String(repeating: "a", count: 10_000)
    mockLogger.info(longMessage, category: .system)

    XCTAssertTrue(mockLogger.recentLogs.first?.message.count == 10_000)
}
```

### 4. Verify Log Levels

```swift
func testOnlyLogsEnabledLevels() {
    let config = LogrConfiguration(
        enabledLevels: [.error, .fault]
    )
    let logger = LogR(configuration: config)

    logger.debug("Debug", category: .debug)
    logger.info("Info", category: .system)
    logger.error("Error", category: .system)

    XCTAssertEqual(logger.recentLogs.count, 1) // Only error logged
    XCTAssertEqual(logger.recentLogs.first?.level, .error)
}
```

### 5. Test Async Operations

```swift
func testAsyncLogging() async throws {
    // Given
    let expectation = XCTestExpectation(description: "Logs written")

    // When
    mockLogger.info("Async log", category: .system)
    await mockLogger.flush()

    // Then
    expectation.fulfill()
    await fulfillment(of: [expectation], timeout: 1.0)

    XCTAssertFalse(mockLogger.recentLogs.isEmpty)
}
```

## Debugging Tests

### Enable Verbose Logging

```swift
func testWithVerboseLogging() {
    let config = LogrConfiguration(logVerbosity: .verbose)
    let logger = LogR(configuration: config)

    logger.info("Test message", category: .test)

    // Logs will include file, function, line in OSLog
}
```

### Print Test Logs

```swift
func testSomething() {
    // When
    viewModel.performAction()

    // Debug - print all logs
    print("\n=== Captured Logs ===")
    for log in mockLogger.recentLogs {
        print("[\(log.level)] \(log.message)")
    }
    print("=====================\n")

    // Assert
    XCTAssertFalse(mockLogger.recentLogs.isEmpty)
}
```

## Summary

Logr provides comprehensive testing support:

✅ **MockLogR** - Full mock implementation for testing
✅ **SwiftUI Previews** - Instant visual feedback
✅ **Unit Tests** - Verify logging behavior
✅ **Integration Tests** - Test with real storage
✅ **Performance Tests** - Measure logging performance

Use `MockLogR` for fast, predictable tests, and real `LogR` instances for integration testing with actual storage and encryption.

## Related Documentation

- [SwiftUI Integration](../docs/Articles/SwiftUIIntegration.md) - Using MockLogR in previews
- [Getting Started](../docs/Articles/GettingStarted.md) - Basic setup
- [Architecture](../docs/Articles/Architecture.md) - Understanding the system
