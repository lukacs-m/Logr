# LogR

[![Swift Package Manager Compatible](https://img.shields.io/badge/SPM-compatible-4BC51D.svg?style=flat)](https://swift.org/package-manager/)
[![Platform](https://img.shields.io/badge/platforms-iOS%2017.0%20%7C%20macOS%2014.0%20%7C%20tvOS%2017.0%20%7C%20watchOS%2010.0-333333.svg)](https://developer.apple.com/swift)
[![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A powerful, persistent logging library for Apple platforms that leverages OSLog while providing encrypted persistent storage, AI-powered analysis, and beautiful SwiftUI visualization.

## Features

- **Persistent Logging**: Unlike standard OSLog entries that are cleared between sessions, LogR maintains logs persistently with optional encrypted storage
- **AI-Powered Analysis** (iOS 26+): Automatic privacy issue detection and intelligent log issue summarization
- **Encryption**: AES-256-GCM (or ChaCha20-Poly1305) encryption for sensitive log data with Keychain-backed keys
- **SwiftUI Integration**: Beautiful, built-in log viewer with filtering, search, statistics, sharing, and AI analysis capabilities
- **Configurable**: Flexible configuration for log retention, levels, cleanup intervals, and verbosity
- **Modular Architecture**: Separate `Logr` core and `LogrUI` modules for flexibility
- **Category System**: Comprehensive enum-based categories with custom support
- **Structured Metadata**: Type-safe key-value metadata on every entry
- **Testing Ready**: Full mock implementation for SwiftUI previews and unit testing
- **Storage Options**: FileSystem and SQLite storage implementations with custom storage protocol
- **Swift 6.2 Compatible**: Built with latest Swift concurrency, sendability, and safety features
- **Performance Optimized**: Logging is `nonisolated` (no `await`, any thread); persistence runs on a background actor

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Core Concepts](#core-concepts)
  - [Log Levels](#log-levels)
  - [Categories](#categories)
  - [Configuration](#configuration)
- [SwiftUI Integration](#swiftui-integration)
- [AI Analysis (iOS 26+)](#ai-analysis-ios-26)
- [Storage](#storage)
- [Privacy & Security](#privacy--security)
- [Testing & Mocking](#testing--mocking)
- [Advanced Usage](#advanced-usage)
- [API Reference](#api-reference)
- [Architecture](#architecture)

## Installation

### Swift Package Manager

Add LogR to your project through Xcode:

1. File → Add Package Dependencies
2. Enter: `https://github.com/lukacs-m/logr`
3. Add `Logr` (and `LogrUI` for the SwiftUI views) to your target

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/lukacs-m/logr", from: "1.3.0")
]
```

### Platform Support

- **iOS** 17.0+
- **macOS** 14.0+
- **tvOS** 17.0+
- **watchOS** 10.0+

**AI Features** require:
- **iOS** 26.0+
- **macOS** 26.0+
- **tvOS** 26.0+
- **watchOS** 12.0+

## Quick Start

### Basic Setup

```swift
import Logr
import LogrUI
import SwiftUI

@main
struct MyApp: App {
    @State private var logger: LogR

    init() {
        do {
            _logger = State(initialValue: try LogR())
        } catch {
            fatalError("Could not initialize LogR: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .logRService(logger)   // equivalent to .environment(\.logService, logger)
        }
    }
}
```

### Basic Logging

```swift
import Logr
import LogrUI
import SwiftUI

struct ContentView: View {
    @Environment(\.logService) private var logger

    var body: some View {
        NavigationStack {
            VStack {
                Button("Log Something") {
                    logger.info("Button was tapped", category: .ui)
                    logger.debug("Processing user action", category: .ui,
                                 metadata: ["screen": "home", "attempt": 1])
                }

                NavigationLink("View Logs") {
                    LogViewer()
                }
            }
        }
    }
}
```

### Logging From Anywhere

Logging is `nonisolated`: no `await`, no main-thread hop, safe from any actor or thread.

```swift
actor SyncEngine {
    let logger: any LogRService

    func sync() async {
        logger.info("Sync started", category: .sync)   // no await — logging is synchronous
    }
}

// Explicit background offloading (Swift 6.2): a @concurrent function runs on the
// concurrent thread pool, and logging from it needs no hop back to any actor.
@concurrent
func processImages(logger: any LogRService) async {
    logger.warning("Image processing is slow", category: .performance)
}

// Reads through the concrete `LogR` see the entry immediately, from any thread.
logger.error("Boom", category: .system)
print(logger.recentLogs.first?.message ?? "")   // "Boom"
```

Through `any LogRService`, `recentLogs` and the other observable properties are `@MainActor`:
SwiftUI reads them on the main actor, and change notifications are batched
(`coalesceWindowMillis`, default 100 ms).

### With Persistent Storage

```swift
import Logr
import LogrUI
import SwiftUI

@main
struct MyApp: App {
    @State private var logger: LogR

    init() {
        do {
            // Using SQLite storage (recommended for large volumes)
            _logger = State(initialValue: try LogR(storage: SQLiteStorage()))

            // Or using FileSystem storage:
            // _logger = State(initialValue: try LogR(storage: FileSystemStorage()))
        } catch {
            fatalError("Could not initialize LogR: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .logRService(logger)
        }
    }
}
```

## Core Concepts

### Log Levels

LogR provides six log levels, each serving a specific purpose:

```swift
public enum LogLevel {
    case debug    // Debug information for development
    case info     // General informational messages
    case notice   // Significant events worth noting
    case warning  // Warning-level messages for non-fatal issues
    case error    // Error conditions that don't halt execution
    case fault    // Critical errors requiring immediate attention
}
```

#### Usage Examples

```swift
// Debug - development information
logger.debug("Cache hit for key: userProfile", category: .cache)

// Info - general information
logger.info("User logged in successfully", category: .authentication)

// Notice - significant events
logger.notice("Payment processed", category: .payment)

// Warning - non-critical issues
logger.warning("API response slow: 3.2s", category: .network)

// Error - recoverable errors
logger.error("Failed to load image", category: .network)

// Fault - critical failures
logger.fault("Database connection lost", category: .database)
```

### Categories

LogR provides 49 predefined categories organized into logical groups:

#### System & Core
```swift
.system, .lifecycle, .initialization, .configuration
```

#### Networking
```swift
.network, .api, .http, .websocket, .ssl
```

#### User Interface
```swift
.ui, .navigation, .animation, .layout, .gesture
```

#### Data & Storage
```swift
.database, .coreData, .fileSystem, .cache, .persistence, .sync
```

#### Security & Authentication
```swift
.authentication, .authorization, .security, .encryption, .keychain, .biometrics
```

#### Performance & Monitoring
```swift
.performance, .memory, .cpu, .battery, .analytics, .crash, .profiling
```

#### External Services
```swift
.push, .location, .camera, .microphone, .contacts, .calendar, .photos
```

#### Business Logic
```swift
.payment, .subscription, .purchase, .user, .content, .search
```

#### Development & Testing
```swift
.debug, .test, .mock
```

#### Custom Categories

For project-specific needs:

```swift
logger.info("Inventory updated", category: .custom("inventory"))
logger.debug("Feature flag enabled", category: .custom("feature-flags"))
```

### Configuration

#### Default Configuration

```swift
// Uses sensible defaults
let logger = try LogR()

// Default configuration:
// - maxLogEntries: 10,000
// - maxLogAge: 7 days
// - enabledLevels: all levels
// - subsystem: Bundle.main.bundleIdentifier
// - cleanupInterval: 1 hour
// - logVerbosity: .verbose
// - categoryLevelOverrides: nil
// - coalesceWindowMillis: 100
// - mirrorToOSLog: true
```

#### Custom Configuration

```swift
let config = LogrConfiguration(
    maxLogEntries: 5_000,              // Keep up to 5,000 entries
    maxLogAge: 24 * 60 * 60,           // Keep logs for 24 hours
    enabledLevels: [.info, .warning, .error, .fault], // Only log important events
    categoryLevelOverrides: [.network: .warning],     // Per-category minimum level
    subsystem: "com.myapp.logging",    // Custom subsystem
    cleanupInterval: 30 * 60,          // Clean up every 30 minutes
    logVerbosity: .normal              // Normal verbosity (less detailed)
)

let logger = try LogR(configuration: config)
```

#### Configuration Options

| Option | Type | Description | Default |
|--------|------|-------------|---------|
| `maxLogEntries` | `Int` | Maximum number of log entries to keep | 10,000 |
| `maxLogAge` | `TimeInterval` | Maximum age of log entries (seconds) | 604,800 (7 days) |
| `enabledLevels` | `Set<LogLevel>` | Which log levels to process | All levels |
| `subsystem` | `String` | OSLog subsystem identifier | Bundle identifier |
| `cleanupInterval` | `TimeInterval` | Cleanup frequency (seconds) | 3,600 (1 hour) |
| `logVerbosity` | `LogVerbosity` | `.verbose` or `.normal` | `.verbose` |
| `categoryLevelOverrides` | `[LogCategory: LogLevel]?` | Minimum level per category (takes precedence over `enabledLevels`) | `nil` |
| `coalesceWindowMillis` | `Int` | Minimum interval between SwiftUI change notifications (data is always current; `0` = notify every log) | 100 |
| `mirrorToOSLog` | `Bool` | Also write each log to OSLog / Console.app | `true` |

## SwiftUI Integration

LogR provides a comprehensive SwiftUI module (`LogrUI`) with a powerful log viewer.

### Using the Log Viewer

```swift
import SwiftUI
import LogrUI

struct LogsView: View {
    var body: some View {
        NavigationStack {
            LogViewer()
        }
    }
}
```

The service is injected once at the app root (see [Quick Start](#quick-start)); `LogViewer`
reads it from the `\.logService` environment. `LogViewer` has no `NavigationStack` of its
own — always host it in one.

### Log Viewer Features

- **Real-time Updates**: Automatically displays new logs as they arrive
- **Advanced Filtering**: Filter by log levels and categories; group by time (relative / by date / by hour)
- **Search**: Full-text search across messages and category names (300 ms debounce)
- **Statistics**: Level/category breakdowns and hourly charts (`LogStatisticsView`, also in the menu)
- **Export**: Share or save logs in JSON, CSV, or plain text formats
- **AI Analysis** (iOS 26+): Privacy issue scanning and issue summarization
- **Expand/Collapse**: Toggle detailed rows (file, function, line)
- **Configurable**: `LogViewer(functionalityFilter: [.sharing])` hides the analyser and statistics entries
- **Dark Mode Support**: Optimized for both light and dark themes

### Environment-Based Access

```swift
struct MyView: View {
    @Environment(\.logService) private var logger

    var body: some View {
        Button("Perform Action") {
            logger.info("Action started", category: .user)
            // Perform action
            logger.info("Action completed", category: .user)
        }
    }
}
```

## AI Analysis (iOS 26+)

LogR includes powerful AI analysis capabilities for iOS 26+ and macOS 26+.

### Privacy Issue Scanning

Automatically detect potential privacy issues in your logs:

```swift
if #available(iOS 26.0, macOS 26.0, *) {
    // Create logger with AI analyzer
    let logger = try LogR(logAnalyser: AIAnalyzer())

    // Scan for privacy issues (`scanForPrivacyIssues` is @MainActor)
    Task { @MainActor in
        let result = try await logger.scanForPrivacyIssues()

        print(result.summary)
        print("Critical: \(result.criticalCount), high: \(result.highCount)")
        for warning in result.warnings {
            print("⚠️ [\(warning.severity)] \(warning.exposureType) at \(warning.file):\(warning.line)")
            print("   \(warning.explanation)")
            print("   Recommendation: \(warning.recommendation)")
        }
    }
}
```

### Issue Summarization

Get AI-powered summaries of critical issues:

```swift
if #available(iOS 26.0, macOS 26.0, *) {
    Task { @MainActor in
        let summary = try await logger.summarizeIssues()

        print(summary.executiveSummary)
        print("Errors: \(summary.totalErrors), warnings: \(summary.totalWarnings), faults: \(summary.totalFaults)")

        for issue in summary.issues {
            print("- [\(issue.severity)] \(issue.title) (\(issue.file):\(issue.line), ×\(issue.occurrences))")
            print("  Fix: \(issue.suggestedFix)")
        }

        print("Patterns: \(summary.patterns)")
        print("Priority actions: \(summary.priorityActions)")
    }
}
```

### AI Features in UI

The LogrUI module automatically integrates AI analysis when available:

```swift
// The "Analyze logs" submenu appears automatically on iOS 26+ when analysis is available
NavigationStack {
    LogViewer()
}
```

Results are also published as `privacyAnalysisResult`, `logIssueSummary` and
`analysisProgress` (all `@MainActor` observable state).

## Storage

LogR supports multiple storage backends with built-in encryption.

### No Storage (OSLog Only)

```swift
// Logs only to OSLog, no persistent storage
let logger = try LogR()
```

### FileSystem Storage

```swift
import Logr

// Single NDJSON file in Documents (pass fileName: to change it)
let storage = try FileSystemStorage()
let logger = try LogR(storage: storage)
```

Features:
- Append-only newline-delimited JSON (NDJSON) in a single file
- Good for moderate log volumes
- Easy to backup and inspect
- Automatic encryption via crypto service

### SQLite Storage (Recommended)

```swift
import Logr

// High-performance SQLite storage
// <Application Support>/<bundle id>/logs.sqlite; or SQLiteStorage(databasePath:)
let storage = try SQLiteStorage()
let logger = try LogR(storage: storage)
```

Features:
- High performance for large volumes
- Efficient querying and filtering
- Optimized for mobile devices
- GRDB-backed for reliability
- Automatic encryption

### Custom Storage

Implement the `LogRPersistence` protocol:

```swift
import Logr

// The protocol is `Sendable`: an actor is the simplest conformer.
actor CloudStorage: LogRPersistence {
    func store(_ entry: EncryptedLogEntry) async throws {
        // Upload to your cloud service
    }

    func fetchEntries() async throws -> [EncryptedLogEntry] {
        // Fetch from your cloud service, oldest first
    }

    func deleteEntries(olderThan date: Date) async throws {
        // Delete old entries
    }

    func deleteEntries(keepingLatest count: Int) async throws {
        // Keep only recent entries
    }

    func clear() async throws {
        // Clear all entries
    }

    func count() async throws -> Int {
        // Return entry count
    }

    // Optional: `store(_ entries:)` (the writer hands over batches of up to 50) and
    // `fetchEntries(limit:)` have default implementations — override them for batching.
}

let logger = try LogR(storage: CloudStorage())
```

## Privacy & Security

LogR is built with privacy and security as first-class concerns.

### Encryption

All stored logs are automatically encrypted using:
- **AES-256-GCM** (default) or **ChaCha20-Poly1305**: Authenticated symmetric encryption with 256-bit keys
- **Keychain Storage**: Encryption keys stored securely in the Keychain (versioned, rotatable)
- **Automatic**: No configuration required

```swift
// Encryption is automatic with storage
let logger = try LogR(storage: SQLiteStorage())

// Logs are encrypted before storage
logger.info("Sensitive operation completed")

// Pick the cipher explicitly, or rotate the key later
let crypto = try LoggerCryptoService(encryptionAlgo: .chacha)   // default is .aes256gcm
let custom = try LogR(storage: SQLiteStorage(), cryptoService: crypto)

try crypto.rotateKey()   // old entries stay readable unless removeOldKeys: true
```

### Custom Crypto Service

Implement your own encryption:

```swift
import Logr

struct MyCustomCrypto: LoggerCryptoServicing {   // the protocol is Sendable — use a struct
    func symmetricEncrypt(object: some Codable & Sendable) throws -> Data {
        // Your encryption logic
    }

    func symmetricDecrypt<T: Codable & Sendable>(encryptedData: Data) throws -> T {
        // Your decryption logic
    }
}

// `try` is for SQLiteStorage(); this LogR overload does not throw
let logger = try LogR(
    storage: SQLiteStorage(),
    cryptoService: MyCustomCrypto()
)
```

### Redacting Sensitive Data

Opt-in `String` helpers keep sensitive values out of your messages:

```swift
logger.info("User logged in: \(email.redactedEmail())", category: .authentication) // j***@example.com
logger.info("Card: \(cardNumber.maskedCreditCard())", category: .payment)          // ****-****-****-1234
logger.info("Token: \(token.redacted(keeping: 4, position: .end))", category: .security)
logger.info("User: \(userID.hashed())", category: .user)                           // truncated SHA-256
```

## Testing & Mocking

LogR includes a full-featured mock for testing and previews.

### SwiftUI Previews

```swift
import LogrUI

#Preview {
    NavigationStack {
        LogViewer()
    }
    // Without an injected service the environment default is a no-op logger,
    // so inject a mock explicitly:
    .environment(\.logService, MockLogR())
}

#Preview("Custom Mock") {
    @Previewable @State var mock = MockLogR()

    return ContentView()
        .logRService(mock)
}
```

### MockLogR Features

- Full `LogRService` protocol compliance (`import LogrUI`)
- Pre-populated with realistic sample data — 5,000 entries by default; `MockLogR(empty: true)` for none, `GenerationConfig`/`GenerationMode.stream` to customize
- In-memory storage (no disk I/O, no Keychain)
- All querying and filtering capabilities
- Export functionality
- Inserts are deferred to the main actor — hop once before asserting in tests (see the Testing docs)

## Advanced Usage

### Querying Logs

```swift
// getLogs is @MainActor — call from a main-actor context.
// Get logs from the last hour
let recentErrors = try logger.getLogs(
    levels: [.error, .fault],
    categories: [.network, .api],
    from: Date().addingTimeInterval(-3600),
    to: Date(),
    limit: 50
)

// Get all authentication logs
let authLogs = try logger.getLogs(
    categories: [.authentication, .authorization, .security]
)

// Get all error-level logs
let errors = try logger.getLogs(levels: [.error])
```

### Exporting Logs

```swift
// Export as JSON (async; empty Data when there are no logs)
let jsonData = try await logger.exportLogs(format: .json)
let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("logs.json")
try jsonData.write(to: url)

// Export as CSV
let csvData = try await logger.exportLogs(format: .csv)

// Export as plain text (human-readable)
let textData = try await logger.exportLogs(format: .txt)
```

### Manual Cleanup

```swift
// Clear all logs
try await logger.clearLogs()

// Flush pending logs to storage
await logger.flush()
```

### Statistics

```swift
let stats = await logger.logStatistics()   // aggregated off the main actor

print(stats.totalCount, stats.errorRate, stats.averageLogsPerHour)
for item in stats.topCategories(3) {
    print(item.category.displayName, item.count)
}
```

### Dropped Logs

If the background writer cannot keep up (backlog over 100,000 entries) or storage keeps
failing, entries are dropped rather than growing memory without bound. The count is
observable via `logger.droppedLogCount` (`@MainActor`); the in-memory cache is unaffected.

### Log Verbosity

Control how much information is logged to OSLog:

```swift
// Verbose mode (default): includes file, function, line
let config = LogrConfiguration(logVerbosity: .verbose)
// Output: "[ui][info] Button tapped (ContentView.swift:viewDidLoad():42)"

// Normal mode: just the message
let config = LogrConfiguration(logVerbosity: .normal)
// Output: "Button tapped"

let logger = try LogR(configuration: config)

// Disable OSLog mirroring entirely
let quiet = LogrConfiguration(mirrorToOSLog: false)
```

### Dependency Injection

LogR is designed for dependency injection:

```swift
// Define your dependencies
protocol AppDependencies {
    var logger: any LogRService { get }
}

class ProductionDependencies: AppDependencies {
    lazy var logger: any LogRService = try! LogR(
        storage: SQLiteStorage(),
        configuration: LogrConfiguration(
            subsystem: "com.myapp.main"
        )
    )
}

// Use in your app
@main
struct MyApp: App {
    let dependencies = ProductionDependencies()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .logRService(dependencies.logger)
        }
    }
}
```

## API Reference

### LogRService Protocol

The main protocol defining logging functionality:

```swift
public protocol LogRService: Observable, Sendable {
    /// Recent logs (in-memory cache), newest first
    @MainActor var recentLogs: Deque<LogEntry> { get }

    /// Whether AI analysis is available
    @MainActor var canAnalyseLogs: Bool { get }

    /// Entries the background writer could not persist (default 0)
    @MainActor var droppedLogCount: Int { get }

    /// AI results and progress (iOS 26+)
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    @MainActor var privacyAnalysisResult: PrivacyAnalysisResult? { get }
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    @MainActor var logIssueSummary: LogIssueSummary? { get }
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    @MainActor var analysisProgress: AnalysisProgress? { get }

    // Core logging — nonisolated: callable from any isolation domain, no await
    nonisolated func log(level: LogLevel, message: @autoclosure () -> String,
                         category: LogCategory, file: String, function: String,
                         line: Int, metadata: [String: LogMetadataValue]?)

    // Management
    func exportLogs(format: ExportFormat) async throws -> Data   // empty Data when there are no logs
    func logStatistics() async -> LogStatistics
    func clearLogs() async throws
    func flush() async

    // AI Analysis (iOS 26+)
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    @MainActor @discardableResult func scanForPrivacyIssues() async throws -> PrivacyAnalysisResult
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    @MainActor @discardableResult func summarizeIssues() async throws -> LogIssueSummary
}

// Provided by protocol extensions
extension LogRService {
    // All six are nonisolated with a lazily-evaluated message.
    // debug's category defaults to .debug; the others default to .system.
    func debug(_ message: @autoclosure () -> String, category: LogCategory = .debug,
               metadata: [String: LogMetadataValue]? = nil)
    func info(...)   func notice(...)   func warning(...)   func error(...)   func fault(...)

    @MainActor func getLogs(levels: Set<LogLevel>? = nil, categories: Set<LogCategory>? = nil,
                            subsystems: Set<String>? = nil, from: Date? = nil, to: Date? = nil,
                            limit: Int? = nil) throws -> [LogEntry]
}
```

Source-location parameters (`file`/`function`/`line`) default to `#file`/`#function`/`#line`
through the extension overloads.

### LogEntry

Represents a single log entry:

```swift
public struct LogEntry: Sendable, Codable, Identifiable, Hashable {
    public let id: String
    public let timestamp: Date
    public let level: LogLevel
    public let category: LogCategory
    public let subsystem: String
    public let message: String
    public let file: String
    public let function: String
    public let line: Int
    public let metadata: [String: LogMetadataValue]?
}
```

### LogLevel

Log severity levels:

```swift
public enum LogLevel: String, CaseIterable {
    case debug
    case info
    case notice
    case warning
    case error
    case fault

    public var osLogType: OSLogType
    public var displayName: String
    public var priority: Int
    public var visualCue: String    // Emoji indicator
}
```

### LogCategory

Comprehensive category system with 49 predefined categories (see [Categories](#categories) section).

### LogrConfiguration

Configuration options for LogR:

```swift
public struct LogrConfiguration: Sendable, Codable {
    public let maxLogEntries: Int                               // 10,000
    public let maxLogAge: TimeInterval                          // 7 days
    public let enabledLevels: Set<LogLevel>                     // all
    public let categoryLevelOverrides: [LogCategory: LogLevel]? // nil
    public let subsystem: String                                // bundle identifier
    public let cleanupInterval: TimeInterval                    // 1 hour
    public let logVerbosity: LogVerbosity                       // .verbose
    public let coalesceWindowMillis: Int                        // 100
    public let mirrorToOSLog: Bool                              // true

    public static let `default`: LogrConfiguration
}
```

## Architecture

LogR is built with a clean, modular architecture:

### Core Components

```
┌─────────────────────────────────────────────────────────┐
│                        LogR                             │
│  @Observable (nonisolated logging)                      │
│  - Manages logging lifecycle                            │
│  - Coordinates with storage and OSLog                   │
│  - Maintains in-memory cache (recentLogs)               │
└────────────┬────────────────────────────────────────────┘
             │
             ├──→ LogRService Protocol
             │    - Public API for logging operations
             │
             ├──→ LogWriterActor
             │    - AsyncStream consumer: encrypt → batch (50) → write
             │    - Retries transient failures (linear backoff)
             │    - Backpressure cap → droppedLogCount
             │
             ├──→ LogRPersistence Protocol
             │    ├── FileSystemStorage
             │    ├── SQLiteStorage
             │    └── Custom implementations
             │
             ├──→ LoggerCryptoServicing Protocol
             │    └── LoggerCryptoService (AES-256-GCM / ChaCha20-Poly1305 + Keychain)
             │
             └──→ LogAIAnalyzer Protocol (iOS 26+)
                  └── AIAnalyzer
                       - Privacy issue detection
                       - Issue summarization
```

### Key Design Decisions

1. **Actor-Based Concurrency**: Background `LogWriterActor` ensures logging never blocks the main thread
2. **Observable Pattern**: SwiftUI-friendly with `@Observable` for reactive updates
3. **Protocol-Oriented**: Easy to extend and mock
4. **Encryption by Default**: All persistent storage is automatically encrypted
5. **Modular**: Separate `Logr` and `LogrUI` packages
6. **Swift 6 Ready**: Full sendability and concurrency safety
7. **Nonisolated Logging**: `log()` appends under a lock and returns — callable from any isolation domain without `await`

### Thread Safety

- Logging (`init`, `log`, `debug`…`fault`) is `nonisolated`; the cache is a lock-protected `Deque`, so a read right after a write sees the entry from any thread
- SwiftUI-facing state (`recentLogs` via `LogRService`, `droppedLogCount`, `canAnalyseLogs`, AI results) is `@MainActor`, with change notifications coalesced onto the main actor
- Persistence and encryption run on the dedicated `LogWriterActor`
- OSLog calls are thread-safe by design

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

LogR is released under the MIT License. See [LICENSE](https://spdx.org/licenses/MIT.html) for details.

## Support & Documentation

- **Documentation**: [Full Documentation](https://lukacs-m.github.io/Logr/)
- **Issues**: [GitHub Issues](https://github.com/lukacs-m/logr/issues)

## Acknowledgments

Built with:
- [KeychainAccess](https://github.com/kishikawakatsumi/KeychainAccess) - Keychain wrapper
- [SQLiteData](https://github.com/pointfreeco/sqlite-data) - SQLite Data models
- [swift-collections](https://github.com/apple/swift-collections) - Deque for the log cache

---
