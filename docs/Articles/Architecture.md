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
│  @Observable (nonisolated logging)                      │
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
             │    └── LoggerCryptoService
             │         - AES-256-GCM (default) / ChaCha20-Poly1305
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
- **Nonisolated logging**: `init`, `log()` and the convenience methods run on the caller's thread; only SwiftUI-facing state (`recentLogs` through the protocol, `droppedLogCount`, `canAnalyseLogs`, AI results) is `@MainActor`
- **In-memory cache**: A `Deque<LogEntry>` (newest first, up to `maxLogEntries`) behind a lock — reads are current from any thread
- **Coalesced observation**: SwiftUI is notified at most once per `coalesceWindowMillis` (default 100 ms)
- **Automatic cleanup**: Periodic cleanup based on age and count limits

**Key Responsibilities:**
- Accepting log messages and routing to OSLog
- Managing in-memory log cache
- Coordinating with storage layer
- Running periodic cleanup
- Providing query and export capabilities

### LogWriterActor

A background actor that handles encryption and all storage operations. `LogR.log()` hands
each entry over synchronously (`ingest` — no `await`, no per-log `Task`); entries flow over
an `AsyncStream` to a single ordered consumer.

```swift
actor LogWriterActor {
    // Producer side — nonisolated, synchronous; called from LogR.log() on any thread
    nonisolated func ingest(_ entry: LogEntry)     // sheds the newest entry past 100,000 pending
    nonisolated func flush() async                  // resumes once everything queued before it is persisted
    nonisolated func clearPending() async throws    // drops the backlog, then clears storage, in order
    nonisolated func shutdown()                     // finishes the stream (called from LogR.deinit)

    // Consumer side — one `for await` loop over the stream:
    //   encrypt → batch of 50 → storage.store(batch)
    //   retry a failed batch ×3 with linear backoff, then drop it
    //   report every drop (shed, encryption failure, exhausted retries) → LogR.droppedLogCount
}
```

**Key Responsibilities:**
- Encrypting entries off the main actor
- Batching writes (50 per batch) and retrying transient storage failures
- Bounding memory under backpressure and accounting every dropped entry
- Ordering `flush()` / `clearLogs()` against in-flight writes (control signals are never dropped)

### Storage Layer

The storage layer is protocol-based for flexibility:

#### LogRPersistence Protocol

Defines the contract for persistent storage:

```swift
public protocol LogRPersistence: Sendable {
    func store(_ entry: EncryptedLogEntry) async throws
    func store(_ entries: [EncryptedLogEntry]) async throws              // default: loops store(_:)
    func fetchEntries() async throws -> [EncryptedLogEntry]              // oldest first
    func fetchEntries(limit: Int?) async throws -> [EncryptedLogEntry]   // default: fetch all, keep newest
    func deleteEntries(olderThan date: Date) async throws
    func deleteEntries(keepingLatest count: Int) async throws
    func clear() async throws
    func count() async throws -> Int
}
```

#### Built-in Implementations

**FileSystemStorage:**
- Single append-only NDJSON file (`Documents/logr_entries.json`)
- Appends are cheap; cleanup and `clear()` rewrite the file
- Legacy JSON-array files migrate automatically on open
- Good for moderate volumes; implemented as an `actor`

**SQLiteStorage:**
- High-performance SQLite database
- Optimized for mobile devices
- Efficient querying and cleanup
- Recommended for production

### Crypto Layer

All logs are encrypted before storage:

#### LoggerCryptoService

- **Algorithm**: AES-256-GCM by default; ChaCha20-Poly1305 via `LoggerCryptoService(encryptionAlgo: .chacha)`
- **Key Size**: 256-bit keys
- **Key Storage**: Secure Keychain (`.whenUnlockedThisDeviceOnly`)
- **Key Versioning**: Supports key rotation without data loss
- **Envelope Format**: Records key version and algorithm (envelopes without an algorithm, pre-1.3, decode as ChaCha20-Poly1305)

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

2. **`log()` runs synchronously on the caller's thread (`nonisolated`):**
   - Checks `enabledLevels` / `categoryLevelOverrides` (the `@autoclosure` message is never evaluated when filtered out)
   - Creates `LogEntry` with metadata
   - Mirrors to OSLog when `mirrorToOSLog` is enabled
   - Prepends to the lock-protected cache and trims to `maxLogEntries`
   - Schedules a coalesced main-actor observation notification (`coalesceWindowMillis`)

3. **Hand-off to the writer:**
   - `writer.ingest(entry)` yields the plaintext entry to the writer's `AsyncStream` — no per-log `Task`
   - Past 100,000 pending entries the newest is shed and counted into `droppedLogCount`

4. **Writer consumer (background actor):**
   - Encrypts with `LoggerCryptoService`
   - Accumulates a batch of 50 and calls `storage.store(_ entries:)`
   - Retries a failed batch ×3 with linear backoff, then drops it (counted)

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
   - Trims entries older than `maxLogAge` from the tail of the newest-first deque (the `maxLogEntries` cap is enforced on every `log()`)
   - Notifies observers

3. **Storage cleanup (background):**
   - Deletes entries older than `maxLogAge`
   - Checks total count
   - If over `maxLogEntries`, deletes oldest

## Thread Safety

### Isolation Model

`LogR` is not `@MainActor` — logging is `nonisolated`, and only the SwiftUI-facing state is
main-actor isolated:

```swift
@Observable
public final class LogR: LogRService {
    public nonisolated var recentLogs: Deque<LogEntry> { get }   // lock-backed snapshot
    @MainActor public private(set) var droppedLogCount: Int
    @MainActor public var canAnalyseLogs: Bool { get }

    public nonisolated func log(level: LogLevel, message: @autoclosure () -> String,
                                category: LogCategory, file: String = #file,
                                function: String = #function, line: Int = #line,
                                metadata: [String: LogMetadataValue]? = nil)
}
```

**Benefits:**
- Call from any actor or thread without `await`
- Read-after-write holds: a read right after `log()` sees the entry
- SwiftUI updates arrive coalesced on the main actor

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
- `LoggerCryptoService`: Thread-safe (lock-protected key cache)

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
actor CloudStorage: LogRPersistence {   // the protocol is Sendable — use an actor
    func store(_ entry: EncryptedLogEntry) async throws {
        // Upload to cloud
    }
    // Implement the other seven methods (two have default implementations)...
}

let logger = try LogR(storage: CloudStorage())
```

### Custom Crypto

Implement `LoggerCryptoServicing` for custom encryption:

```swift
struct CustomCrypto: LoggerCryptoServicing {   // Sendable — use a struct
    func symmetricEncrypt(object: some Codable & Sendable) throws -> Data {
        // Your encryption
    }

    func symmetricDecrypt<T: Codable & Sendable>(encryptedData: Data) throws -> T {
        // Your decryption
    }
}

let logger = LogR(cryptoService: CustomCrypto())   // no try: this overload does not throw
```

### Custom AI Analyzer

Implement `LogAIAnalyzer` for custom analysis:

```swift
@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
actor CustomAI: LogAIAnalyzer {
    nonisolated var isAvailable: Bool { true }

    func scanForPrivacyIssues(logs: [LogEntry]) async throws -> PrivacyAnalysisResult {
        try await scanForPrivacyIssues(logs: logs, onProgress: { _ in })
    }

    func scanForPrivacyIssues(logs: [LogEntry],
                              onProgress: @escaping @MainActor @Sendable (AnalysisProgress) -> Void)
        async throws -> PrivacyAnalysisResult {
        // Your AI service
    }

    func summarizeIssues(logs: [LogEntry]) async throws -> LogIssueSummary {
        try await summarizeIssues(logs: logs, onProgress: { _ in })
    }

    func summarizeIssues(logs: [LogEntry],
                         onProgress: @escaping @MainActor @Sendable (AnalysisProgress) -> Void)
        async throws -> LogIssueSummary {
        // Your AI service
    }
}

let logger = try LogR(logAnalyser: CustomAI())
```

## Design Principles

### 1. Non-Blocking

Logging never blocks the caller:
- `log()` is synchronous: an OSLog write, a lock-protected append and a stream yield — no per-log `Task`
- Encryption and storage happen in the background writer actor
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
