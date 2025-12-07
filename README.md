# LogR

[![Swift Package Manager Compatible](https://img.shields.io/badge/SPM-compatible-4BC51D.svg?style=flat)](https://swift.org/package-manager/)
[![Platform](https://img.shields.io/badge/platforms-iOS%2017.0%20%7C%20macOS%2014.0%20%7C%20tvOS%2017.0%20%7C%20watchOS%2010.0-333333.svg)](https://developer.apple.com/swift)
[![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A powerful, persistent logging library for Apple platforms that leverages OSLog while providing encrypted persistent storage, AI-powered analysis, and beautiful SwiftUI visualization.

## Features

- **Persistent Logging**: Unlike standard OSLog entries that are cleared between sessions, LogR maintains logs persistently with optional encrypted storage
- **AI-Powered Analysis** (iOS 26+): Automatic privacy issue detection and intelligent log issue summarization
- **Encryption**: Built-in symmetric encryption for sensitive log data using the Keychain
- **SwiftUI Integration**: Beautiful, built-in log viewer with filtering, search, sharing, and AI analysis capabilities
- **Privacy-First**: Apple privacy system integration with automatic redaction of sensitive data
- **Configurable**: Flexible configuration for log retention, levels, cleanup intervals, and verbosity
- **Modular Architecture**: Separate `Logr` core and `LogrUI` modules for flexibility
- **Category System**: Comprehensive enum-based categories with custom support
- **Testing Ready**: Full mock implementation for SwiftUI previews and unit testing
- **Storage Options**: FileSystem and SQLite storage implementations with custom storage protocol
- **Swift 6.2 Compatible**: Built with latest Swift concurrency, sendability, and safety features
- **Performance Optimized**: Background log writing with actor-based concurrency

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
3. Select the version and add to your target

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/lukacs-m/logr", from: "1.0.0")
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
import SwiftUI

@main
struct MyApp: App {
    let logger = LogR()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .logRService(logger)
        }
    }
}
```

### Basic Logging

```swift
struct ContentView: View {
    @Environment(\.logr) private var logger

    var body: some View {
        VStack {
            Button("Log Something") {
                logger.info("Button was tapped", category: .ui)
                logger.debug("Processing user action", category: .ui)
            }

            NavigationLink("View Logs") {
                LogrUIView()
            }
        }
    }
}
```

### With Persistent Storage

```swift
import Logr

@main
struct MyApp: App {
    // Using SQLite storage (recommended for large volumes)
    let logger = LogR(storage: SQLiteStorage())

    // Or using FileSystem storage
    // let logger = LogR(storage: FileSystemStorage())

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

LogR provides 47 predefined categories organized into logical groups:

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
let logger = LogR()

// Default configuration:
// - maxLogEntries: 10,000
// - maxLogAge: 7 days
// - enabledLevels: all levels
// - subsystem: Bundle.main.bundleIdentifier
// - cleanupInterval: 1 hour
// - logVerbosity: .verbose
```

#### Custom Configuration

```swift
let config = LogrConfiguration(
    maxLogEntries: 5_000,              // Keep up to 5,000 entries
    maxLogAge: 24 * 60 * 60,           // Keep logs for 24 hours
    enabledLevels: [.info, .warning, .error, .fault], // Only log important events
    subsystem: "com.myapp.logging",    // Custom subsystem
    cleanupInterval: 30 * 60,          // Clean up every 30 minutes
    logVerbosity: .normal              // Normal verbosity (less detailed)
)

let logger = LogR(configuration: config)
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

## SwiftUI Integration

LogR provides a comprehensive SwiftUI module (`LogrUI`) with a powerful log viewer.

### Using the Log Viewer

```swift
import SwiftUI
import LogrUI

struct ContentView: View {
  @State private var logger = LogR(storage: SQLiteStorage())
  
    var body: some View {
        NavigationStack {
            LogrUIView()
        }
        .logRService(logger)
    }
}
```

### Log Viewer Features

- **Real-time Updates**: Automatically displays new logs as they arrive
- **Advanced Filtering**: Filter by log levels, categories
- **Search**: Full-text search across messages, categories, and subsystems
- **Export**: Export logs in JSON, CSV, or plain text formats
- **AI Analysis** (iOS 26+): Privacy issue scanning and issue summarization
- **Dark Mode Support**: Optimized for both light and dark themes

### Environment-Based Access

```swift
struct MyView: View {
    @Environment(\.logr) private var logger

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
    let analyzer = AIAnalyzer()
    let logger = LogR(logAnalyser: analyzer)

    // Scan for privacy issues
    Task {
        let result = try await logger.scanForPrivacyIssues()

        print("Privacy Score: \(result.privacyScore)")
        for warning in result.warnings {
            print("⚠️ \(warning.message)")
            print("   Severity: \(warning.severity)")
            print("   Recommendation: \(warning.recommendation)")
        }
    }
}
```

### Issue Summarization

Get AI-powered summaries of critical issues:

```swift
if #available(iOS 26.0, macOS 26.0, *) {
    Task {
        let summary = try await logger.summarizeIssues()

        print("Summary: \(summary.summary)")
        print("\nKey Issues:")
        for issue in summary.keyIssues {
            print("- \(issue)")
        }

        print("\nRecommendations:")
        for recommendation in summary.recommendations {
            print("- \(recommendation)")
        }

        print("\nAffected Categories:")
        for category in summary.affectedCategories {
            print("- \(category)")
        }
    }
}
```

### AI Features in UI

The LogrUI module automatically integrates AI analysis when available:

```swift
// The AI analysis button appears automatically on iOS 26+
NavigationStack {
    LogrUIView()
}
```

## Storage

LogR supports multiple storage backends with built-in encryption.

### No Storage (OSLog Only)

```swift
// Logs only to OSLog, no persistent storage
let logger = LogR()
```

### FileSystem Storage

```swift
import Logr

// Simple file-based storage
let storage = FileSystemStorage()
let logger = LogR(storage: storage)
```

Features:
- Simple JSON-based storage
- Good for moderate log volumes
- Easy to backup and inspect
- Automatic encryption via crypto service

### SQLite Storage (Recommended)

```swift
import Logr

// High-performance SQLite storage
let storage = SQLiteStorage()
let logger = LogR(storage: storage)
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

class CloudStorage: LogRPersistence {
    func store(_ entry: EncryptedLogEntry) async throws {
        // Upload to your cloud service
    }

    func fetchEntries(limit: Int?) async throws -> [EncryptedLogEntry] {
        // Fetch from your cloud service
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
}

let logger = LogR(storage: CloudStorage())
```

## Privacy & Security

LogR is built with privacy and security as first-class concerns.

### Encryption

All stored logs are automatically encrypted using:
-  **AES** or **ChaChapoly**: Industry-standard symmetric encryption
- **Keychain Storage**: Encryption keys stored securely in the Keychain
- **Automatic**: No configuration required

```swift
// Encryption is automatic with storage
let logger = LogR(storage: SQLiteStorage())

// Logs are encrypted before storage
logger.info("Sensitive operation completed")
```

### Custom Crypto Service

Implement your own encryption:

```swift
import Logr

class MyCustomCrypto: LoggerCryptoServicing {
    func symmetricEncrypt<T: Encodable>(object: T) throws -> Data {
        // Your encryption logic
    }

    func symmetricDecrypt<T: Decodable>(encryptedData: Data) throws -> T {
        // Your decryption logic
    }
}

let logger = LogR(
    storage: SQLiteStorage(),
    cryptoService: MyCustomCrypto()
)
```

## Testing & Mocking

LogR includes a full-featured mock for testing and previews.

### SwiftUI Previews

```swift
#Preview {
    NavigationStack {
        LogrUIView()
    }
    // MockLogR is automatically used via environment default
}

#Preview("Custom Mock") {
    @Previewable @State var mock = MockLogR()

    return ContentView()
        .logRService(mock)
}
```

### MockLogR Features

- Full `LogRService` protocol compliance
- Pre-populated with realistic sample data
- In-memory storage (no disk I/O)
- All querying and filtering capabilities
- Export functionality
- Perfect for development and testing

## Advanced Usage

### Querying Logs

```swift
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
// Export as JSON
if let jsonData = logger.exportLogs(format: .json) {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("logs.json")
    try? jsonData.write(to: url)
}

// Export as CSV
if let csvData = logger.exportLogs(format: .csv) {
    // Share or save CSV
}

// Export as plain text
if let textData = logger.exportLogs(format: .txt) {
    // Human-readable format
}
```

### Manual Cleanup

```swift
// Clear all logs
try await logger.clearLogs()

// Flush pending logs to storage
await logger.flush()
```

### Log Verbosity

Control how much information is logged to OSLog:

```swift
// Verbose mode (default): includes file, function, line
let config = LogrConfiguration(logVerbosity: .verbose)
// Output: "[ui][info] Button tapped (ContentView.swift:viewDidLoad():42)"

// Normal mode: just the message
let config = LogrConfiguration(logVerbosity: .normal)
// Output: "Button tapped"

let logger = LogR(configuration: config)
```

### Dependency Injection

LogR is designed for dependency injection:

```swift
// Define your dependencies
protocol AppDependencies {
    var logger: LogRService { get }
}

class ProductionDependencies: AppDependencies {
    lazy var logger: LogRService = LogR(
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
@MainActor
public protocol LogRService: Observable, Sendable {
    /// Recent logs (in-memory cache)
    var recentLogs: [LogEntry] { get }

    /// Whether AI analysis is available
    var canAnalyseLogs: Bool { get }

    /// Privacy analysis result (iOS 26+)
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    var privacyAnalysisResult: PrivacyAnalysisResult? { get }

    /// Log issue summary (iOS 26+)
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    var logIssueSummary: LogIssueSummary? { get }

    // Core logging
    func log(level: LogLevel, message: String, category: LogCategory,
             file: String, function: String, line: Int)

    // Convenience methods
    func debug(_ message: String, category: LogCategory)
    func info(_ message: String, category: LogCategory)
    func notice(_ message: String, category: LogCategory)
    func warning(_ message: String, category: LogCategory)
    func error(_ message: String, category: LogCategory)
    func fault(_ message: String, category: LogCategory)

    // Management
    func exportLogs(format: ExportFormat) -> Data?
    func clearLogs() async throws
    func flush() async

    // AI Analysis (iOS 26+)
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    func scanForPrivacyIssues() async throws -> PrivacyAnalysisResult
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    func summarizeIssues() async throws -> LogIssueSummary
}
```

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
    public var visualQueue: String  // Emoji indicator
}
```

### LogCategory

Comprehensive category system with 47+ predefined categories (see [Categories](#categories) section).

### LogrConfiguration

Configuration options for LogR:

```swift
public struct LogrConfiguration: Sendable, Codable {
    public let maxLogEntries: Int
    public let maxLogAge: TimeInterval
    public let enabledLevels: Set<LogLevel>
    public let subsystem: String
    public let cleanupInterval: TimeInterval
    public let logVerbosity: LogVerbosity

    public static let `default`: LogrConfiguration
}
```

## Architecture

LogR is built with a clean, modular architecture:

### Core Components

```
┌─────────────────────────────────────────────────────────┐
│                        LogR                             │
│  @Observable @MainActor                                 │
│  - Manages logging lifecycle                            │
│  - Coordinates with storage and OSLog                   │
│  - Maintains in-memory cache (recentLogs)               │
└────────────┬────────────────────────────────────────────┘
             │
             ├──→ LogRService Protocol
             │    - Public API for logging operations
             │
             ├──→ LogWriterActor
             │    - Background actor for async storage writes
             │    - Queues and batches log entries
             │    - Ensures non-blocking logging
             │
             ├──→ LogRPersistence Protocol
             │    ├── FileSystemStorage
             │    ├── SQLiteStorage
             │    └── Custom implementations
             │
             ├──→ LoggerCryptoServicing Protocol
             │    └── LoggerCryptoService (AES / ChaChaPoly + Keychain)
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

### Thread Safety

- All public APIs are `@MainActor` isolated
- Background storage operations use dedicated actor
- Encryption happens off main thread
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

---

Made with ❤️ for the Swift community
