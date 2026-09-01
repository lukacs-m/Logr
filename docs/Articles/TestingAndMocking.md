---
layout: default
title: Testing and Mocking
nav_order: 8
parent: Logr Documentation
---

# Testing and Mocking

Learn how to test your logging code and use MockLogR for development and testing.

[← Back to Documentation](../index.md)

## Overview

Logr provides comprehensive testing support through `MockLogR`, a full-featured mock
implementation that works seamlessly in SwiftUI previews and unit tests. All examples use
the Swift Testing framework (`@Suite`, `@Test`, `#expect`, `#require`) — the same framework
Logr's own test suite uses.

## MockLogR

The `MockLogR` class implements `LogRService` with in-memory storage and pre-populated
sample data. It ships in the `LogrUI` product (`import LogrUI`), is created and read on the
main actor, and its `log()` **defers** inserts to the main actor — there is no synchronous
read-after-write (unlike the real `LogR`).

### Features

- Full `LogRService` protocol compliance (queries, export and statistics come from the protocol extensions)
- Pre-populated with realistic sample logs — 5,000 generated entries by default; `MockLogR(empty: true)` for none
- `GenerationConfig(totalEntries:timeRange:levelDistribution:categories:subsystems:)` and `GenerationMode.instant` / `.stream(chunks:delay:)` for custom data
- In-memory storage (no disk I/O, no Keychain); cache capped at 100 entries
- Canned AI results for the iOS 26+ views
- Deferred inserts — hop to the main actor once before asserting

### Basic Usage

```swift
import LogrUI

@MainActor
func demo() async {
    let mock = MockLogR(empty: true)

    // Use it like a real logger
    mock.info("Test message", category: .network)
    mock.error("Test error", category: .database)

    // Let the deferred inserts land, then read
    await Task { @MainActor in }.value
    print("Total logs: \(mock.recentLogs.count)")   // 2
}
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
    let mock = MockLogR(empty: true)

    // Add specific test logs (inserts land asynchronously — fine for previews)
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
    NavigationStack {
        LogViewer()
    }
    .environment(\.logService, MockLogR(empty: true))
}

#Preview("With Logs") {
    NavigationStack {
        LogViewer()
    }
    .environment(\.logService, MockLogR())
}

#Preview("Streaming") {
    NavigationStack {
        LogViewer()
    }
    .environment(\.logService,
                 MockLogR(config: GenerationConfig(totalEntries: 2_000),
                          mode: .stream(chunks: 20, delay: 0.5)))
}

#Preview("Many Errors") {
    let mock = MockLogR(empty: true)

    for i in 1...20 {
        mock.error("Error \(i)", category: .network)
    }

    return NavigationStack {
        LogViewer()
    }
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
    let mock = MockLogR(empty: true)
    mock.error("Test error 1", category: .network)
    mock.error("Test error 2", category: .database)

    return MyLogView()
        .logRService(mock)
}
```

## Unit Testing

Use `MockLogR` to test logging behavior in your code, and a real `LogR` (with an in-memory
key store) when a test needs synchronous read-after-write.

### Setup

Shared scaffolding for the examples below:

```swift
import Foundation
import Logr
import LogrUI          // MockLogR
import Testing
import os

/// Keeps tests off the real Keychain. The lock makes the class Sendable.
final class InMemoryKeychainStore: KeychainStore, Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: [String: Data]())
    func data(forKey key: String) throws -> Data? { storage.withLock { $0[key] } }
    func set(_ data: Data, forKey key: String) throws { storage.withLock { $0[key] = data } }
    func remove(forKey key: String) throws { storage.withLock { $0[key] = nil } }
}

func makeTestLogger(storage: LogRPersistence? = nil,
                    configuration: LogrConfiguration = .default) throws -> LogR {
    LogR(storage: storage,
         cryptoService: try LoggerCryptoService(store: InMemoryKeychainStore()),
         configuration: configuration)
}

/// MockLogR defers inserts to the main actor; awaiting a fresh main-actor task
/// guarantees earlier inserts have landed before reading `recentLogs`.
@MainActor
func settle() async {
    await Task { @MainActor in }.value
}
```

Mark suites that touch `MockLogR` as `@MainActor` (its `init` and `recentLogs` are
main-actor isolated), and call `settle()` before asserting. A real `LogR` needs neither:
its cache is updated synchronously under a lock.

### Testing Log Output

```swift
@MainActor
@Suite("MyViewModel logging")
struct MyViewModelTests {
    let mockLogger: MockLogR
    let viewModel: MyViewModel

    init() {
        mockLogger = MockLogR(empty: true)
        viewModel = MyViewModel(logger: mockLogger)
    }

    @Test("Success path logs an info entry")
    func logsOnSuccess() async {
        await viewModel.performAction()
        await settle()

        let infoLogs = mockLogger.recentLogs.filter { $0.level == .info }
        #expect(infoLogs.count == 1)
        #expect(infoLogs.first?.message == "Action completed successfully")
        #expect(infoLogs.first?.category == .user)
    }

    @Test("Failure path logs an error")
    func logsOnError() async {
        viewModel.shouldFail = true

        await viewModel.performAction()
        await settle()

        let errorLogs = mockLogger.recentLogs.filter { $0.level == .error }
        #expect(!errorLogs.isEmpty)
        #expect(errorLogs.first?.message.contains("failed") == true)
    }
}
```

### Testing Log Levels

Use a real `LogR` — read-after-write is synchronous:

```swift
@MainActor
@Suite("LogR behaviour")
struct LogRBehaviourTests {
    @Test("Disabled levels are dropped")
    func disabledLevels() throws {
        let logger = try makeTestLogger(
            configuration: LogrConfiguration(enabledLevels: [.info, .warning, .error, .fault]))

        logger.debug("Debug message", category: .debug)
        logger.error("Error", category: .system)

        #expect(logger.recentLogs.count == 1)
        #expect(logger.recentLogs.first?.level == .error)
    }
}
```

### Testing Categories

```swift
@Test("Network operations log to network categories")
func networkCategories() async {
    let mock = MockLogR(empty: true)
    let viewModel = MyViewModel(logger: mock)

    await viewModel.fetchData()
    await settle()

    #expect(mock.recentLogs.contains { $0.category == .network || $0.category == .api })
}
```

### Testing Log Queries

`getLogs` is `@MainActor` and comes from the protocol extension:

```swift
@Test("getLogs filters by level, category and date")
func queries() throws {
    let logger = try makeTestLogger()
    logger.info("Info message", category: .system)
    logger.error("Error message", category: .network)
    logger.fault("Fault message", category: .system)

    #expect(try logger.getLogs(levels: [.error, .fault]).count == 2)
    #expect(try logger.getLogs(categories: [.network]).map(\.message) == ["Error message"])
    #expect(try logger.getLogs(from: .now.addingTimeInterval(-60), to: .now).count == 3)
}
```

### Testing Export

`exportLogs` is `async throws -> Data` and returns empty `Data` when there are no logs.
JSON dates are ISO-8601; the CSV header is
`Timestamp,Level,Category,Subsystem,Message,File,Function,Line,Metadata`.

```swift
@Test("Exports JSON and CSV")
func export() async throws {
    let logger = try makeTestLogger()
    logger.info("Test log", category: .system)

    let json = try await logger.exportLogs(format: .json)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    #expect(try decoder.decode([LogEntry].self, from: json).count == 1)

    let csvData = try await logger.exportLogs(format: .csv)
    let csv = try #require(String(data: csvData, encoding: .utf8))
    #expect(csv.hasPrefix("Timestamp,Level,Category,Subsystem,Message"))
    #expect(csv.contains("Test log"))
}

@Test("Export of an empty cache is empty Data, not an error")
func emptyExport() async throws {
    #expect(try await makeTestLogger().exportLogs(format: .json).isEmpty)
}
```

### Testing Clear Logs

```swift
@Test("clearLogs empties the cache")
func clear() async throws {
    let logger = try makeTestLogger()
    logger.info("Log 1", category: .system)
    logger.info("Log 2", category: .system)
    #expect(logger.recentLogs.count == 2)

    try await logger.clearLogs()

    #expect(logger.recentLogs.isEmpty)
}
```

## Integration Testing

Test the full Logr system with actual storage.

### Setup Test Storage

Give every test its own temporary database path; `SQLiteStorage(databasePath:)` creates
intermediate directories itself.

```swift
@MainActor
@Suite("Integration", .serialized)
struct LogRIntegrationTests {
    private func temporaryDatabasePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("logr-\(UUID().uuidString).sqlite").path
    }
}
```

### Testing Persistence

The second instance must share the crypto service (or at least the key store) — a fresh
random key cannot decrypt the first instance's entries. History is merged asynchronously
after init, so poll briefly instead of sleeping a fixed second:

```swift
@Test("Entries persist and are reloaded by a fresh instance")
func persistsAcrossInstances() async throws {
    let path = temporaryDatabasePath()
    let crypto = try LoggerCryptoService(store: InMemoryKeychainStore())

    let first = LogR(storage: try SQLiteStorage(databasePath: path), cryptoService: crypto)
    first.info("Persistent log", category: .system)
    await first.flush()

    let second = LogR(storage: try SQLiteStorage(databasePath: path), cryptoService: crypto)
    for _ in 0..<50 where second.recentLogs.isEmpty {
        try await Task.sleep(for: .milliseconds(20))
    }

    #expect(second.recentLogs.contains { $0.message == "Persistent log" })
}
```

### Testing Retention

Age-based cleanup runs on a main-run-loop timer every `cleanupInterval`, which is not
deterministic in a test process — test retention through `maxLogEntries` instead, which is
enforced synchronously on every `log()`:

```swift
@Test("maxLogEntries caps the in-memory cache, newest first")
func retentionCap() throws {
    let logger = try makeTestLogger(configuration: LogrConfiguration(maxLogEntries: 3))

    for i in 1...5 { logger.info("Message \(i)", category: .system) }

    #expect(logger.recentLogs.map(\.message) == ["Message 5", "Message 4", "Message 3"])
}
```

### Testing Encryption

```swift
@Test("Stored entries never contain the plaintext message")
func storedEntriesAreEncrypted() async throws {
    let storage = try SQLiteStorage(databasePath: temporaryDatabasePath())
    let logger = try makeTestLogger(storage: storage)

    logger.info("Secret message", category: .system)
    await logger.flush()

    let stored = try await storage.fetchEntries()
    #expect(stored.count == 1)
    #expect(stored.allSatisfy { $0.data.range(of: Data("Secret message".utf8)) == nil })
}
```

## Testing Custom Implementations

### Testing Custom Storage

```swift
@Suite("Custom storage")
struct CustomStorageTests {
    @Test("store / fetch round-trip, oldest first")
    func storeAndFetch() async throws {
        let storage = MyCustomStorage()   // your `actor MyCustomStorage: LogRPersistence`

        let entries = (1...3).map { i in
            EncryptedLogEntry(id: "e\(i)",
                              timestamp: Date().addingTimeInterval(Double(i)),
                              data: Data("d\(i)".utf8))
        }

        try await storage.store(entries)          // batch requirement
        #expect(try await storage.fetchEntries().map(\.id) == ["e1", "e2", "e3"])
        #expect(try await storage.fetchEntries(limit: 2).map(\.id) == ["e2", "e3"])

        try await storage.deleteEntries(keepingLatest: 1)
        #expect(try await storage.count() == 1)

        try await storage.clear()
        #expect(try await storage.count() == 0)
    }
}
```

### Testing Custom Crypto

```swift
@Suite("Custom crypto")
struct CustomCryptoTests {
    @Test("encrypt / decrypt round-trip")
    func roundTrip() throws {
        let crypto = MyCustomCrypto(key: SymmetricKey(size: .bits256))
        let original = LogEntry(level: .info, category: .system,
                                subsystem: "test", message: "Test message")

        let encrypted = try crypto.symmetricEncrypt(object: original)
        let decrypted: LogEntry = try crypto.symmetricDecrypt(encryptedData: encrypted)

        #expect(decrypted == original)
        #expect(encrypted.range(of: Data("Test message".utf8)) == nil)
    }
}
```

## Test Utilities

### Helper Extensions

```swift
@MainActor
extension MockLogR {
    /// Adds `count` test logs and waits for the deferred inserts to land.
    func addTestLogs(count: Int) async {
        for i in 1...count {
            info("Test log \(i)", category: .test)
        }
        await Task { @MainActor in }.value
    }
}
```

Prefer `try await mock.clearLogs()` over any fire-and-forget clearing — un-awaited clears
are exactly what makes tests flaky.

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

@Test func usesFixture() {
    let log = LogEntry.fixture(level: .error, message: "Test error")
    #expect(log.level == .error)
}
```

## Performance Testing

Swift Testing has no `measure` API — time with `ContinuousClock` and keep hard timing
assertions out of CI:

```swift
@Test("Logging throughput baseline")
func loggingThroughput() async throws {
    let logger = try makeTestLogger()

    let elapsed = ContinuousClock().measure {
        for i in 1...1_000 {
            logger.info("Performance test \(i)", category: .performance)
        }
    }
    await logger.flush()

    print("Logged 1,000 entries in \(elapsed)")   // informational
}

@MainActor
@Test("Query performance baseline")
func queryThroughput() throws {
    let logger = try makeTestLogger(configuration: LogrConfiguration(maxLogEntries: 10_000))
    for i in 1...10_000 {
        logger.info("Log \(i)", category: .system)
    }

    let elapsed = ContinuousClock().measure {
        _ = try? logger.getLogs(levels: [.info])
    }
    print("Query took \(elapsed)")
}
```

## Best Practices

### 1. Use MockLogR for Previews and UI Tests

```swift
// ✅ Good - fast, predictable
#Preview {
    ContentView()
        .environment(\.logService, MockLogR())
}

// ❌ Bad - touches the Keychain and disk in a preview
#Preview {
    ContentView()
        .environment(\.logService, try! LogR(storage: SQLiteStorage()))
}
```

### 2. Clean Up Between Tests

Swift Testing creates a fresh suite instance for every test, so a mock created in `init()`
(or inline in the test) starts clean — there is nothing to tear down. Give integration
tests a unique temporary database path each.

### 3. Test Edge Cases

```swift
@Test("Empty and very long messages are kept")
func edgeCases() throws {
    let logger = try makeTestLogger()

    logger.info("", category: .system)
    logger.info(String(repeating: "a", count: 10_000), category: .system)

    #expect(logger.recentLogs.count == 2)
    #expect(logger.recentLogs.first?.message.count == 10_000)
}
```

### 4. Verify Log Levels

Covered by `disabledLevels()` above — build the `LogrConfiguration` with the levels you
expect in production and assert the filtered levels never reach `recentLogs`.

### 5. Test Async Operations

`flush()` suspends until everything queued before it is persisted:

```swift
@Test("flush waits for pending writes")
func flushWaits() async throws {
    let storage = try SQLiteStorage(databasePath: temporaryDatabasePath())
    let logger = try makeTestLogger(storage: storage)

    logger.info("Async log", category: .system)
    await logger.flush()

    #expect(try await storage.count() == 1)
}
```

## Debugging Tests

### Enable Verbose Logging

```swift
@Test func verboseLogging() throws {
    let logger = try makeTestLogger(configuration: LogrConfiguration(logVerbosity: .verbose))

    logger.info("Test message", category: .test)
    // OSLog output includes file, function and line.
    // Pass mirrorToOSLog: false instead to keep test output quiet.
}
```

### Print Test Logs

```swift
// Inside a @MainActor test, after settle():
print("\n=== Captured Logs ===")
for log in mockLogger.recentLogs {
    print("[\(log.level.rawValue)] \(log.message)")
}
print("=====================\n")
```

## Summary

Logr provides comprehensive testing support:

✅ **MockLogR** - Full mock implementation for previews and tests (`import LogrUI`)
✅ **SwiftUI Previews** - Instant visual feedback
✅ **Swift Testing** - `@Suite` / `@Test` / `#expect` / `#require` throughout
✅ **Integration Tests** - Real storage and encryption with an in-memory key store
✅ **Performance Baselines** - `ContinuousClock().measure`

Use `MockLogR` for fast, predictable tests (remember its deferred inserts), and real `LogR`
instances — with `InMemoryKeychainStore` — for read-after-write assertions and integration
testing with actual storage and encryption.

## Related Documentation

- [SwiftUI Integration](./SwiftUIIntegration.md) - Using MockLogR in previews
- [Getting Started](./GettingStarted.md) - Basic setup
- [Architecture](./Architecture.md) - Understanding the system
