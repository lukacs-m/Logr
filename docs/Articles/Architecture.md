---
layout: default
title: Architecture
nav_order: 3
parent: Logr Documentation
---

# Architecture Overview

Understand the internal design and architecture of Logr.

[← Back to Documentation](../index.md)

## Overview

Logr is built with a clean, modular architecture that prioritizes performance, thread safety, and extensibility. This guide explains how the different components work together.

## Component Diagram

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
             │    - Convenience methods (debug, info, etc.)
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
             │    └── LoggerCryptoService
             │         - Encryption
             │         - Keychain storage for keys
             │         - Key versioning & rotation
             │
             └──→ LogAIAnalyzer Protocol (iOS 26+)
                  └── AIAnalyzer
                       - Apple Intelligence integration
                       - Privacy issue detection
                       - Issue summarization
```

## Core Components

### LogR

The main logging class that implements `LogRService`:

- **Decorated with `@Observable`**: Enables reactive SwiftUI updates
- **`@MainActor` isolated**: All public APIs are main-actor isolated for thread safety
- **In-memory cache**: Maintains recent logs (up to `maxLogEntries`) for quick access
- **Automatic cleanup**: Periodic cleanup based on age and count limits

**Key Responsibilities:**
- Accepting log messages and routing to OSLog
- Managing in-memory log cache
- Coordinating with storage layer
- Running periodic cleanup
- Providing query and export capabilities

### LogWriterActor

A background actor that handles all storage operations:

```swift
actor LogWriterActor {
    private let storage: LogRPersistence
    private var pending: [EncryptedLogEntry] = []
    private var isWritingTask: Task<Void, Never>?

    func enqueue(_ entry: EncryptedLogEntry) {
        // Queues entry and starts write task if needed
    }

    func flush() async {
        // Writes all pending entries
    }
}
```

**Key Responsibilities:**
- Queueing log entries for write
- Writing to storage without blocking main thread
- Handling storage errors gracefully

### Storage Layer

The storage layer is protocol-based for flexibility:

#### LogRPersistence Protocol

Defines the contract for persistent storage:

```swift
public protocol LogRPersistence: Sendable {
    func store(_ entry: EncryptedLogEntry) async throws
    func fetchEntries() async throws -> [EncryptedLogEntry]
    func deleteEntries(olderThan date: Date) async throws
    func deleteEntries(keepingLatest count: Int) async throws
    func clear() async throws
    func count() async throws -> Int
}
```

#### Built-in Implementations

**FileSystemStorage:**
- Simple JSON-based file storage
- One file per log entry
- Good for moderate volumes
- Easy to inspect and backup

**SQLiteStorage:**
- High-performance SQLite database
- Optimized for mobile devices
- Efficient querying and cleanup
- Recommended for production

### Crypto Layer

All logs are encrypted before storage:

#### LoggerCryptoService

- **Algorithm**: ChaCha20-Poly1305 (fast, modern stream cipher)
- **Key Size**: 256-bit keys
- **Key Storage**: Secure Keychain (`.whenUnlockedThisDeviceOnly`)
- **Key Versioning**: Supports key rotation without data loss
- **Envelope Format**: Includes version for forward compatibility

**Encryption Flow:**
```
LogEntry → JSON Encoding → Encryption → Versioned Envelope → Storage
```

**Decryption Flow:**
```
Storage → Versioned Envelope → Decryption → JSON Decoding → LogEntry
```

### AI Analysis Layer (iOS 26+)

Optional AI-powered analysis using Apple Intelligence:

#### AIAnalyzer

- **Privacy Scanning**: Detects PII, credentials, and sensitive data
- **Issue Summarization**: Identifies patterns and provides recommendations
- **On-Device**: All processing happens on-device
- **Availability Check**: Gracefully degrades when unavailable

## Data Flow

### Logging Flow

1. **User calls logging method:**
   ```swift
   logger.info("Message", category: .network)
   ```

2. **LogR processes on main actor:**
   - Checks if level is enabled
   - Creates `LogEntry` with metadata
   - Adds to in-memory cache
   - Logs to OSLog

3. **Background encryption & storage:**
   - `Task` created with crypto service reference
   - Entry encrypted with `LoggerCryptoService`
   - `EncryptedLogEntry` created
   - Enqueued to `LogWriterActor`

4. **Actor writes to storage:**
   - Entry added to pending queue
   - Background task started (if not running)
   - All pending entries written
   - Storage errors logged

### Query Flow

1. **User queries logs:**
   ```swift
   let logs = try logger.getLogs(levels: [.error])
   ```

2. **LogR filters in-memory cache:**
   - Applies level filter
   - Applies category filter
   - Applies date range filter
   - Applies limit

3. **Returns filtered results**

### Cleanup Flow

1. **Timer triggers (configurable interval)**

2. **In-memory cleanup:**
   - Filters out entries older than `maxLogAge`
   - Updates `recentLogs` array

3. **Storage cleanup (background):**
   - Deletes entries older than `maxLogAge`
   - Checks total count
   - If over `maxLogEntries`, deletes oldest

## Thread Safety

### Main Actor Isolation

All public APIs are `@MainActor` isolated:

```swift
@Observable
@MainActor
public final class LogR: LogRService, Sendable {
    // All public methods run on main actor
}
```

**Benefits:**
- SwiftUI-friendly
- No race conditions in public API
- Predictable execution context

### Background Processing

Storage operations use dedicated actor:

```swift
actor LogWriterActor {
    // All storage writes happen here
}
```

**Benefits:**
- Main thread never blocks on I/O
- Efficient batching of writes
- Automatic serialization of access

### Sendability

All types conform to `Sendable` where appropriate:

- `LogEntry`: Immutable struct, naturally `Sendable`
- `LogLevel`, `LogCategory`: Enums, naturally `Sendable`
- `LogRPersistence`: Requires `Sendable` conformance
- `LoggerCryptoService`: Thread-safe with `Mutex`

## Performance Characteristics

### Memory Usage

- **In-memory cache**: Bounded by `maxLogEntries` (default: 10,000)
- **Each log entry**: ~200-500 bytes (varies with message length)
- **Typical memory**: 2-5 MB for 10,000 entries
- **Automatic cleanup**: Prevents unbounded growth

### Storage

- **SQLite database**: Efficient, grows linearly with log count
- **Automatic cleanup**: Prevents unbounded growth

## Extensibility Points

### Custom Storage

Implement `LogRPersistence` for custom storage:

```swift
class CloudStorage: LogRPersistence {
    func store(_ entry: EncryptedLogEntry) async throws {
        // Upload to cloud
    }
    // Implement other methods...
}

let logger = try LogR(storage: CloudStorage())
```

### Custom Crypto

Implement `LoggerCryptoServicing` for custom encryption:

```swift
class CustomCrypto: LoggerCryptoServicing {
    func symmetricEncrypt<T: Codable>(object: T) throws -> Data {
        // Your encryption
    }

    func symmetricDecrypt<T: Codable>(encryptedData: Data) throws -> T {
        // Your decryption
    }
}

let logger = LogR(cryptoService: CustomCrypto())
```

### Custom AI Analyzer

Implement `LogAIAnalyzer` for custom analysis:

```swift
@available(iOS 26.0, *)
class CustomAI: LogAIAnalyzer {
    var isAvailable: Bool { true }

    func scanForPrivacyIssues(logs: [LogEntry]) async throws -> PrivacyAnalysisResult {
        // Your AI service
    }

    func summarizeIssues(logs: [LogEntry]) async throws -> LogIssueSummary {
        // Your AI service
    }
}

let logger = try LogR(logAnalyser: CustomAI())
```

## Design Principles

### 1. Non-Blocking

Logging never blocks the caller:
- Main actor methods return immediately
- Storage happens in background actor
- OSLog is non-blocking by design

### 2. Observable

SwiftUI-friendly with `@Observable`:
- Reactive updates to `recentLogs`
- No need for Combine subscriptions
- Automatic view updates

### 3. Protocol-Oriented

Extensible through protocols:
- Storage layer: `LogRPersistence`
- Crypto layer: `LoggerCryptoServicing`
- AI layer: `LogAIAnalyzer`

### 4. Type-Safe

Strong typing throughout:
- `LogLevel` enum prevents invalid levels
- `LogCategory` enum provides structured categories
- No magic strings or numbers

### 5. Testable

Easy to test with mocks:
- `MockLogR` for SwiftUI previews
- Protocol-based design enables mocking
- In-memory operations for testing

## Summary

Logr's architecture provides:

✅ **Performance** - Non-blocking, efficient storage
✅ **Safety** - Thread-safe, strong typing, sendability
✅ **Extensibility** - Protocol-based, customizable
✅ **Reliability** - Automatic cleanup, error handling
✅ **Simplicity** - Clear responsibilities, minimal API surface

The modular design allows you to use Logr's components independently or replace them with your own implementations while maintaining the benefits of the overall system.

## Related Documentation

- [Getting Started](./GettingStarted.md) - Basic setup and usage
- [Storage and Persistence](./StorageAndPersistence.md) - Storage implementation details
- [Privacy and Security](./PrivacyAndSecurity.md) - Encryption details
