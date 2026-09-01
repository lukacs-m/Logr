---
layout: default
title: Logr Documentation
nav_order: 1
---

# Logr

A powerful, persistent logging library for Apple platforms that leverages OSLog while providing encrypted persistent storage, AI-powered analysis, and beautiful SwiftUI visualization.

## Overview

Logr is a comprehensive logging solution that combines the power of Apple's OSLog framework with persistent storage capabilities, encryption, and AI-powered analysis. It's designed to be simple to use, highly configurable, and production-ready.

### Key Features

- **Persistent Logging**: Unlike standard OSLog entries that are cleared between sessions, Logr maintains logs persistently with optional encrypted storage
- **AI-Powered Analysis** (iOS 26+): Automatic privacy issue detection and intelligent log issue summarization using Apple Intelligence
- **Encryption**: Built-in AES-256-GCM (or ChaCha20-Poly1305) encryption for sensitive log data using secure Keychain storage
- **SwiftUI Integration**: Beautiful, built-in log viewer (`LogViewer`) with filtering, search, sharing, and AI analysis
- **Privacy-First**: OSLog output keeps the system's default `<private>` redaction for interpolated messages; persistent storage is encrypted, and opt-in redaction helpers (`redactedEmail()`, `hashed()`, …) are included
- **Configurable**: Flexible configuration for log retention, levels, cleanup intervals, and verbosity
- **Modular Architecture**: Separate `Logr` core and `LogrUI` modules for flexibility
- **49 Categories**: Comprehensive enum-based categories organized into 9 logical groups
- **Testing Ready**: Full `MockLogR` implementation for SwiftUI previews and unit testing
- **Storage Options**: FileSystem and SQLite storage implementations with custom storage protocol
- **Swift 6.2 Compatible**: Built with latest Swift concurrency, sendability, and safety features
- **Performance Optimized**: Logging is `nonisolated` (no `await`, any thread); persistence runs on a background actor

### Quick Start

```swift
import Logr
import LogrUI
import SwiftUI

@main
struct MyApp: App {
    @State private var logger: LogR

    init() {
        do {
            _logger = State(initialValue: try LogR(storage: SQLiteStorage()))
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

struct ContentView: View {
    @Environment(\.logService) private var logger

    var body: some View {
        Button("Test") {
            logger.info("Button tapped", category: .ui)
        }
    }
}
```

## Documentation

### Getting Started

- [Getting Started](./Articles/GettingStarted.md) - Installation, setup, and your first logs
- [Architecture](./Articles/Architecture.md) - Understand how Logr works internally

### Core Types

| Type | Description |
|------|-------------|
| `LogR` | Main logging class, `@Observable`; logging is `nonisolated`, SwiftUI-facing state is `@MainActor` |
| `LogRService` | Protocol defining the logging API |
| `LogEntry` | Represents a single log entry |
| `LogLevel` | Six log levels: debug, info, notice, warning, error, fault |
| `LogCategory` | 49 predefined categories + custom |
| `LogrConfiguration` | Configuration for retention, cleanup, verbosity, per-category overrides, notification coalescing, OSLog mirroring |
| `LogVerbosity` | Control log detail level (verbose/normal) |

### Storage

- [Storage and Persistence](./Articles/StorageAndPersistence.md) - Storage options and custom implementations

| Type | Description |
|------|-------------|
| `LogRPersistence` | Protocol for custom storage implementations |
| `FileSystemStorage` | Append-only NDJSON file storage |
| `SQLiteStorage` | High-performance SQLite storage (recommended) |
| `EncryptedLogEntry` | Encrypted log entry for storage |

### Privacy & Security

- [Privacy and Security](./Articles/PrivacyAndSecurity.md) - Encryption and privacy features

| Type | Description |
|------|-------------|
| `LoggerCryptoServicing` | Protocol for custom encryption |
| `LoggerCryptoService` | AES-256-GCM (default) / ChaCha20-Poly1305 implementation with key rotation |
| `LoggerCryptoError` | Encryption-related errors |
| `KeychainStore` | Secure key storage |
| `KeychainAccessStore` | Default Keychain-backed `KeychainStore` |

### AI Analysis (iOS 26+)

- [AI Analysis](./Articles/AIAnalysis.md) - Privacy scanning and issue summarization

| Type | Description |
|------|-------------|
| `LogAIAnalyzer` | Protocol for AI analysis |
| `AIAnalyzer` | Apple Intelligence integration (actor) |
| `AnalyzerConfiguration` | Chunking / concurrency tuning for `AIAnalyzer` |
| `PrivacyAnalysisResult` | Privacy scan results |
| `PrivacyWarning` | Individual privacy warning |
| `LogSeverity` | Severity levels: critical, high, medium, low |
| `LogIssueSummary` | AI-generated issue summary |
| `LogIssue` | Individual issue in a summary |
| `AnalysisProgress` | Progress of a running analysis |
| `AIAnalyzerError` | AI analysis errors |

### SwiftUI Integration

- [SwiftUI Integration](./Articles/SwiftUIIntegration.md) - LogViewer and environment setup

| Type | Description |
|------|-------------|
| `LogViewer` | Complete log viewing UI component (`functionalityFilter:` toggles menu groups) |
| `LogStatisticsView` | Statistics dashboard (totals, rates, charts) |
| `CompactLogStatisticsView` | Inline statistics card |
| `AIAnalysisView` / `PrivacyWarningsView` / `IssueSummaryView` | AI result views (iOS 26+) |
| `LogStatistics` | Aggregate counts and rates (`await logger.logStatistics()`) |
| `ExportFormat` | Export formats: JSON, CSV, TXT |

### Testing & Mocking

- [Testing and Mocking](./Articles/TestingAndMocking.md) - Test your logging code

| Type | Description |
|------|-------------|
| `MockLogR` | Full mock implementation for previews and tests (`import LogrUI`) |

### Errors

| Type | Description |
|------|-------------|
| `LogRErrors` | General logging errors |
| `LogExportError` | Export encoding errors |

## Platform Support

- iOS 17.0+
- macOS 14.0+
- tvOS 17.0+
- watchOS 10.0+

**AI Features** require:
- iOS 26.0+
- macOS 26.0+
- tvOS 26.0+
- watchOS 12.0+

## Installation

### Swift Package Manager

Add Logr to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/lukacs-m/logr", from: "1.3.0")
]
```

Or add via Xcode:
1. File → Add Package Dependencies
2. Enter: `https://github.com/lukacs-m/logr`
3. Select version and add to target

## Architecture

Logr uses a clean, modular architecture:

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

## Best Practices

### Log Levels

- Use `.debug` for detailed troubleshooting information (disable in production)
- Use `.info` for tracking normal app flow and operations
- Use `.notice` for significant but expected events
- Use `.warning` for unexpected but recoverable conditions
- Use `.error` for failures that affect specific features
- Use `.fault` for critical errors that may cause instability

### Categories

Organize logs by system area using the 49 predefined categories:

```swift
logger.info("User logged in", category: .authentication)
logger.error("Request failed", category: .network)
logger.debug("Cache hit", category: .cache)
logger.fault("Database error", category: .database)
```

### Configuration

Balance performance and storage:

```swift
// Development
let devConfig = LogrConfiguration(
    maxLogEntries: 10_000,
    maxLogAge: 7 * 24 * 60 * 60,
    enabledLevels: Set(LogLevel.allCases),
    logVerbosity: .verbose
)

// Production
let prodConfig = LogrConfiguration(
    maxLogEntries: 5_000,
    maxLogAge: 24 * 60 * 60,
    enabledLevels: [.info, .warning, .error, .fault],
    logVerbosity: .normal
)
```

### Privacy

Never log sensitive data directly:

```swift
// ❌ Bad - logs sensitive data
logger.info("User password: \(password)", category: .authentication)

// ✅ Good - logs safely
logger.info("User authentication successful", category: .authentication)
```

With storage encryption enabled, all logs are automatically encrypted before persistence.

Logr is optimized for minimal performance impact:
- Background actor prevents main thread blocking
- Lazy message evaluation with `@autoclosure`
- Efficient in-memory cache with size limits
- Automatic cleanup prevents unbounded growth

## License

Logr is released under the MIT License.

## Support

- **Issues**: [GitHub Issues](https://github.com/lukacs-m/logr/issues)
- **Discussions**: [GitHub Discussions](https://github.com/lukacs-m/logr/discussions)

## Acknowledgments

Built with:
- [KeychainAccess](https://github.com/kishikawakatsumi/KeychainAccess) - Keychain wrapper
- [SQLiteData](https://github.com/pointfreeco/sqlite-data) - SQLite Data models
- [swift-collections](https://github.com/apple/swift-collections) - Deque for the log cache
