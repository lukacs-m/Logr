# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Logr is a Swift logging framework for Apple platforms (iOS 17+, macOS 14+, tvOS 17+, watchOS 10+). It provides encrypted persistent storage, SwiftUI integration, and optional AI-powered log analysis (iOS/macOS 26+). Built with Swift 6.2 and full concurrency safety.

## Build & Test Commands

```bash
swift build                              # Build the package
swift test --parallel                    # Run all tests (preferred, matches CI)
swift test --filter "testDebugLogging"   # Run a single test by name
```

CI runs on macOS 15 with latest Xcode: `swift test --parallel`

## Code Formatting

SwiftFormat is integrated as a build plugin. Configuration is in `.swiftformat`:
- Swift 6.2, 4-space indent, 115 char max width
- Excludes Tests and Package.swift
- Key rules: `after-first` wrapping, `before-first` collection wrapping, no-space ranges

## Architecture

### Two Library Targets

- **Logr** (`Sources/Logr/`): Core logging library — models, protocols, storage, encryption, AI analysis
- **LogrUI** (`Sources/LogrUI/`): SwiftUI views for log browsing, statistics, and AI analysis results

### Core Design

**LogR** is the central `@Observable` (nonisolated) class implementing `LogRService`. It:
- Maintains an in-memory `Deque<LogEntry>` cache (configurable max, default 10,000) behind a `SafeMutex`, so logging and reads are thread-safe from any isolation domain; the `@Observable` change notification is dispatched (coalesced) to the main actor
- Delegates persistent writes to **LogWriterActor** (background actor, batched writes of 50)
- Integrates with OSLog for system-level logging
- Coordinates encryption and cleanup automatically

**Key protocols:**
- `LogRService` — public logging API (`@Observable`, `Sendable`). Logging (`log`/`debug`/`info`/…) and `init` are `nonisolated` (callable from any domain); the observable state that drives SwiftUI (`recentLogs`, `droppedLogCount`, `canAnalyseLogs`, AI results) is `@MainActor`
- `LogRPersistence` — storage abstraction (FileSystem or SQLite implementations)
- `LoggerCryptoServicing` — AES-256-GCM / ChaCha20-Poly1305 encryption with Keychain-backed keys
- `LogAIAnalyzer` — Apple Intelligence analysis (iOS 26+ only, via `FoundationModels`)

### Data Flow

Logging calls (nonisolated, any domain) → `LogR` (lock-protected in-memory cache) → `LogWriterActor` (background batching) → `LogRPersistence` (encrypted storage via `LoggerCryptoService`)

### Storage Options

- **FileSystemStorage** (actor): JSON files in Documents directory, good for moderate volume
- **SQLiteStorage**: GRDB-backed database in Application Support, recommended for large volume

### Concurrency Model

- Logging (`init`, `log`, and the convenience methods) is `nonisolated` — callable from any isolation domain with no `await`. `LogR` is `@Observable` but not `@MainActor`; its `recentLogs` cache lives behind a `SafeMutex`, so synchronous read-after-write holds from any thread
- Only the `@Observable` state read by SwiftUI is `@MainActor` (`recentLogs`, `droppedLogCount`, `canAnalyseLogs`, the AI results + analysis methods); the change notification is coalesced and emitted on the main actor
- Background storage writes happen on dedicated `LogWriterActor`
- `LogrUI` target uses `@defaultIsolation(MainActor.self)`
- Both targets enable `NonisolatedNonsendingByDefault` and `InferIsolatedConformances` upcoming features
- Logging methods use `@autoclosure` for lazy message evaluation

### Models

- **LogLevel**: debug, info, notice, warning, error, fault (with priority ordering)
- **LogCategory**: 47 predefined categories + `.custom(String)` for project-specific use
- **LogEntry**: Immutable log record with source location, metadata, and category
- **EncryptedLogEntry**: Encrypted wrapper for persistent storage
- **LogrConfiguration**: Controls retention (max entries/age), enabled levels, per-category overrides, verbosity

### Testing

Tests use Swift Testing framework (`@Suite`, `@Test` attributes). `MockLogR` in `Sources/LogrUI/Mock+Previews/` provides a full `LogRService` implementation for SwiftUI previews and unit tests with in-memory storage and sample data.

### Dependencies

- **KeychainAccess** (4.2.2+): Keychain storage for encryption keys
- **SQLiteData** (1.3.0+): SQLite via GRDB
- **swift-collections** (1.3.0+): Deque for log cache
- **SwiftFormat** (0.58.6+): Build plugin for code formatting
