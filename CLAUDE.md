# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Logr is a Swift logging framework for Apple platforms (iOS 17+, macOS 14+, tvOS 17+, watchOS 10+). It provides encrypted persistent storage, SwiftUI integration, and optional AI-powered log analysis (iOS/macOS 26+). Built with Swift 6.3 (`swift-tools-version: 6.3`, Swift 6 language mode) and full concurrency safety.

## Build & Test Commands

```bash
swift build                              # Build the package
swift test --parallel                    # Run all tests (preferred, matches CI)
swift test --filter "testDebugLogging"   # Run a single test by name
swift test --filter ReadmeSnippets       # Compile every README snippet and check it is reproduced verbatim
swift package generate-documentation --target Logr --warnings-as-errors     # DocC, exactly as CI runs it
swift package generate-documentation --target LogrUI --warnings-as-errors
```

CI (`.github/workflows/swift.yml`) runs on `macos-26` with the latest Xcode: `swift test --parallel`, then DocC for both targets with warnings as errors. `.github/workflows/docs.yml` builds the combined DocC archive on every push to `develop` and deploys it to GitHub Pages (https://lukacs-m.github.io/Logr/).

## Documentation

There is no hand-written documentation folder. Three places describe the library, each with one job:

- **Doc comments** on public symbols are the API reference (DocC). Signatures, defaults, isolation, availability and behaviour are documented there and nowhere else. `Sources/Logr/Logr.docc` and `Sources/LogrUI/LogrUI.docc` hold only the module landing pages (Overview + Topics), no articles and no code.
- **README.md** is a short entry point (~200 lines): pitch, install, quick start, code map, links. Every ```swift block in it is reproduced verbatim in `Tests/LogrTests/ReadmeSnippetsTests.swift`, which compiles them; `readmeSnippetsAreVerbatim` checks the pairing (blank lines, comments, imports and `@main` are ignored; a block starting with `// Package.swift` is exempt).
- **This file** records what cannot be derived from the code: commands, architecture facts, and the rules below.

Definition of done for any change:

1. A changed `public` declaration updates its doc comment in the same change. Symbol links (``Name``) must resolve: run the two DocC commands above.
2. A behaviour change the README describes updates the README, and any edit to a README snippet is mirrored in `ReadmeSnippetsTests.swift`. Run `swift test --filter ReadmeSnippets`.
3. A change to `Package.swift` or to the writer constants (batch size, attempts, backpressure cap) updates the Architecture and Dependencies sections of this file.

Do not add Markdown documentation files to the repository. Durable explanations go in doc comments.

## Code Formatting

SwiftFormat is a declared package dependency but is **not** wired up as a build plugin — run the `swiftformat` CLI manually. Configuration is in `.swiftformat`:
- `--swiftversion 6.3`, 4-space indent, 115 char max width
- Excludes Tests and Package.swift
- Key rules: `after-first` wrapping, `before-first` collection wrapping, no-space ranges

## Architecture

### Two Library Targets

- **Logr** (`Sources/Logr/`): Core logging library — models, protocols, storage, encryption, AI analysis
- **LogrUI** (`Sources/LogrUI/`): SwiftUI views for log browsing, statistics, and AI analysis results

### Core Design

**LogR** is the central `@Observable` (nonisolated) class implementing `LogRService`. It:
- Maintains an in-memory `Deque<LogEntry>` cache (configurable max, default 10,000) behind a `SafeMutex`, so logging and reads are thread-safe from any isolation domain; the `@Observable` change notification is dispatched (coalesced) to the main actor
- Delegates persistent writes to **LogWriterActor** (background actor fed by an `AsyncStream`; batched writes of 50, a failing batch gets 3 attempts with linear backoff (50 ms, 100 ms) before being dropped, and a 100,000-entry backpressure cap sheds the newest entries — every drop is surfaced through `droppedLogCount`)
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

- **FileSystemStorage** (actor): single append-only NDJSON file `Documents/logr_entries.json` (one entry per line; legacy JSON-array files are migrated on open), good for moderate volume
- **SQLiteStorage**: GRDB-backed database in Application Support, recommended for large volume

### Concurrency Model

- Logging (`init`, `log`, and the convenience methods) is `nonisolated` — callable from any isolation domain with no `await`. `LogR` is `@Observable` but not `@MainActor`; its `recentLogs` cache lives behind a `SafeMutex`, so synchronous read-after-write holds from any thread
- Only the `@Observable` state read by SwiftUI is `@MainActor` (`recentLogs`, `droppedLogCount`, `canAnalyseLogs`, the AI results + analysis methods); the change notification is coalesced and emitted on the main actor
- Background storage writes happen on dedicated `LogWriterActor`
- `LogrUI` target uses `@defaultIsolation(MainActor.self)`
- Both targets enable the `NonisolatedNonsendingByDefault` and `InferIsolatedConformances` upcoming features; `Logr` also enables `ExistentialAny` and `ImmutableWeakCaptures`
- Logging methods use `@autoclosure` for lazy message evaluation

### Models

- **LogLevel**: debug, info, notice, warning, error, fault (with priority ordering)
- **LogCategory**: 49 predefined categories + `.custom(String)` for project-specific use
- **LogEntry**: Immutable log record with source location, metadata, and category
- **EncryptedLogEntry**: Encrypted wrapper for persistent storage
- **LogrConfiguration**: Controls retention (max entries/age), enabled levels, per-category overrides, verbosity, observation coalescing window (`coalesceWindowMillis`, default 100 ms), OSLog mirroring (`mirrorToOSLog`)

### Testing

Tests use Swift Testing framework (`@Suite`, `@Test` attributes). The test target depends on both `Logr` and `LogrUI`. Real `LogR` tests back `LoggerCryptoService` with an in-memory `KeychainStore` (`MockKeychainService` in `LogrTests.swift`) and use the non-throwing `LogR(cryptoService:)` init, so no Keychain or disk is touched. `MockLogR` in `Sources/LogrUI/Mock+Previews/` provides a full `LogRService` implementation for SwiftUI previews and unit tests with in-memory storage and sample data; its `log()` defers the insert to the main actor, so tests must hop to the main actor before reading `recentLogs`.

### Dependencies

- **KeychainAccess** (4.2.2+): Keychain storage for encryption keys
- **SQLiteData** (1.12.0+): SQLite via GRDB
- **swift-collections** (1.5.1+): Deque for log cache
- **SwiftFormat** (0.61.0+): Formatter — declared dependency for CLI use, not a build plugin
- **swift-docc-plugin** (1.5.0+): `swift package generate-documentation`
