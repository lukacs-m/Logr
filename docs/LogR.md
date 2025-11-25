# ``Logr``

A powerful, persistent logging library for Apple platforms that leverages OSLog while providing encrypted persistent storage, AI-powered analysis, and beautiful SwiftUI visualization.

## Overview

LogR is a comprehensive logging solution that combines the power of Apple's OSLog framework with persistent storage capabilities, encryption, and AI-powered analysis. It's designed to be simple to use, highly configurable, and production-ready.

### Key Features

- **Persistent Logging**: Unlike standard OSLog entries that are cleared between sessions, LogR maintains logs persistently with optional encrypted storage
- **AI-Powered Analysis** (iOS 26+): Automatic privacy issue detection and intelligent log issue summarization using Apple Intelligence
- **Encryption**: Built-in ChaCha20-Poly1305 encryption for sensitive log data using secure Keychain storage
- **SwiftUI Integration**: Beautiful, built-in log viewer (`LogViewer`) with filtering, search, sharing, and AI analysis
- **Privacy-First**: Apple privacy system integration with automatic redaction of sensitive data in OSLog
- **Configurable**: Flexible configuration for log retention, levels, cleanup intervals, and verbosity
- **Modular Architecture**: Separate `Logr` core and `LogrUI` modules for flexibility
- **47+ Categories**: Comprehensive enum-based categories organized into 9 logical groups
- **Testing Ready**: Full `MockLogR` implementation for SwiftUI previews and unit testing
- **Storage Options**: FileSystem and SQLite storage implementations with custom storage protocol
- **Swift 6 Compatible**: Built with latest Swift concurrency, sendability, and safety features
- **Performance Optimized**: Background log writing with actor-based concurrency

### Quick Start

```swift
import Logr
import SwiftUI

@main
struct MyApp: App {
    @State private var logger = LogR(storage: SQLiteStorage())

    var body: some Scene {
        WindowGroup {
            ContentView()
                .logRService(logger)
        }
    }
}

struct ContentView: View {
    @Environment(\.logr) private var logger

    var body: some View {
        Button("Test") {
            logger.info("Button tapped", category: .ui)
        }
    }
}
```

## Topics

### Getting Started

- <doc:GettingStarted>
- <doc:Architecture>

### Core Types

- ``LogR``
- ``LogRService``
- ``LogEntry``
- ``LogLevel``
- ``LogCategory``
- ``LogrConfiguration``
- ``LogVerbosity``

### Storage

- <doc:StorageAndPersistence>
- ``LogRPersistence``
- ``FileSystemStorage``
- ``SQLiteStorage``
- ``EncryptedLogEntry``

### Privacy & Security

- <doc:PrivacyAndSecurity>
- ``LoggerCryptoServicing``
- ``LoggerCryptoService``
- ``LoggerCryptoError``
- ``KeychainStore``

### AI Analysis (iOS 26+)

- <doc:AIAnalysis>
- ``LogAIAnalyzer``
- ``AIAnalyzer``
- ``PrivacyAnalysisResult``
- ``PrivacyWarning``
- ``PrivacySeverity``
- ``LogIssueSummary``
- ``AIAnalyzerError``

### SwiftUI Integration

- <doc:SwiftUIIntegration>
- ``LogViewer``
- ``ExportFormat``

### Testing & Mocking

- <doc:TestingAndMocking>
- ``MockLogR``

### Models & Errors

- ``LogrErrors``
- ``ExportFormat``

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

Add LogR to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/lukacs-m/logr", from: "1.0.0")
]
```

Or add via Xcode:
1. File → Add Package Dependencies
2. Enter: `https://github.com/lukacs-m/logr`
3. Select version and add to target

## Architecture

LogR uses a clean, modular architecture:

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
             │
             ├──→ LogRPersistence Protocol
             │    ├── FileSystemStorage
             │    ├── SQLiteStorage (GRDB)
             │    └── Custom implementations
             │
             ├──→ LoggerCryptoServicing Protocol
             │    └── LoggerCryptoService (ChaCha20-Poly1305 + Keychain)
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

## Best Practices

### Log Levels

- Use `.debug` for detailed troubleshooting information (disable in production)
- Use `.info` for tracking normal app flow and operations
- Use `.notice` for significant but expected events
- Use `.warning` for unexpected but recoverable conditions
- Use `.error` for failures that affect specific features
- Use `.fault` for critical errors that may cause instability

### Categories

Organize logs by system area using the 47+ predefined categories:

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

LogR is optimized for minimal performance impact:
- Background actor prevents main thread blocking
- Lazy message evaluation with `@autoclosure`
- Efficient in-memory cache with size limits
- Automatic cleanup prevents unbounded growth

## License

LogR is released under the MIT License.

## Support

- **Documentation**: [Full DocC Documentation](https://docs.example.com/logr)
- **Issues**: [GitHub Issues](https://github.com/lukacs-m/logr/issues)
- **Discussions**: [GitHub Discussions](https://github.com/lukacs-m/logr/discussions)

## Acknowledgments

Built with:
- [GRDB.swift](https://github.com/groue/GRDB.swift) - SQLite toolkit
- [KeychainAccess](https://github.com/kishikawakatsumi/KeychainAccess) - Keychain wrapper
- [SQLiteData](https://github.com/pointfreeco/sqlite-data) - SQLite Data models
