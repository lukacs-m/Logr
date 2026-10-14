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
swift package generate-documentation --target LogrTesting --warnings-as-errors
```

CI (`.github/workflows/swift.yml`) runs on `macos-26` with the latest Xcode: SwiftFormat lint (a pinned, checksummed 0.63.1 release), `swift test --parallel`, then DocC for all three library targets with warnings as errors. A `platforms` job builds the `Logr-Package` scheme (every library) for the iOS, tvOS and watchOS simulators with `xcodebuild` (not `swift build --triple`, which forces Logr's deployment target onto dependencies and breaks swift-perception). `.github/workflows/docs.yml` builds the combined DocC archive (`Logr`, `LogrUI`, `LogrTesting`) on every push to `develop` and deploys it to GitHub Pages (https://lukacs-m.github.io/Logr/).

## Documentation

There is no hand-written documentation folder. Three places describe the library, each with one job:

- **Doc comments** on public symbols are the API reference (DocC). Signatures, defaults, isolation, availability and behaviour are documented there and nowhere else. `Sources/Logr/Logr.docc` and `Sources/LogrUI/LogrUI.docc` hold only the module landing pages (Overview + Topics), no articles and no code.
- **README.md** is a short entry point (~200 lines): pitch, install, quick start, code map, links. Every ```swift block in it is reproduced verbatim in `Tests/LogrTests/ReadmeSnippetsTests.swift`, which compiles them; `readmeSnippetsAreVerbatim` checks the pairing (blank lines, comments, imports and `@main` are ignored; a block starting with `// Package.swift` is exempt).
- **This file** records what cannot be derived from the code: commands, architecture facts, and the rules below.

Definition of done for any change:

1. A changed `public` declaration updates its doc comment in the same change. Symbol links (``Name``) must resolve: run the DocC commands above.
2. A behaviour change the README describes updates the README, and any edit to a README snippet is mirrored in `ReadmeSnippetsTests.swift`. Run `swift test --filter ReadmeSnippets`.
3. A change to `Package.swift` or to the writer constants (batch size, attempts, backpressure cap) updates the Architecture and Dependencies sections of this file.

Do not add Markdown documentation files to the repository. Durable explanations go in doc comments.

## Code Formatting

Lint with the `swiftformat` CLI, 0.63.1 or newer (`--minversion` in `.swiftformat`; CI uses exactly 0.63.1, so bump the CI version, its checksum and `--minversion` together). The declared SwiftFormat package dependency resolves an older version that `--minversion` rejects, so do not `swift run swiftformat`. Configuration is in `.swiftformat`:
- `--swiftversion 6.3`, 4-space indent, 115 char max width
- Excludes Tests and Package.swift
- Key rules: `after-first` wrapping, `before-first` collection wrapping, no-space ranges

## Architecture

### Library Targets

- **Logr** (`Sources/Logr/`): Core logging library — models, protocols, storage, encryption, AI analysis
- **LogrUI** (`Sources/LogrUI/`): SwiftUI views for log browsing, statistics, and AI analysis results
- **LogrTesting** (`Sources/LogrTesting/`): test doubles for consumers' test targets (`InMemoryKeychainStore`)

### Core Design

**LogR** is the central `@Observable` (nonisolated) class implementing `LogRService`. It:
- Maintains an in-memory `Deque<LogEntry>` cache (`maxLogEntries`, default 10,000, clamped to 100...100,000 by both `LogrConfiguration` inits; the upper bound matches the writer's backpressure cap) behind a `SafeMutex`, exposed as `LogEntries` (an O(1) copy-on-write, newest-first `RandomAccessCollection`; no `Deque` in the public API), so logging and reads are thread-safe from any isolation domain; the `@Observable` change notification is dispatched (coalesced) to the main actor
- Delegates persistence to **LogWriterActor**, created from a `LogStorage` (`.memoryOnly` creates no writer). All `LogR` and `LoggerCryptoService` inits are non-throwing: the writer opens the storage (and applies a pending clear, which needs no key), checks the key, then reads history (up to `maxLogEntries`, handed to `LogR` via `persistedHistory()`; a failed read only logs, as in 1.x) on its own actor. Until the storage opens and the key reads, entries wait as plaintext (counted against the backpressure cap) and `persistenceStatus` (`.opening` until the first attempt ends) is `.waitingForProtectedData` (key throws `LoggerCryptoError.keyTemporarilyUnavailable`, i.e. `errSecInteractionNotAllowed`) or `.failed`; it retries every 30 s and on `UIApplication.protectedDataDidBecomeAvailableNotification` (not on watchOS or macOS). A clear before storage opens is applied when it opens; cleanup runs through the writer, one pass at a time
- The writer itself: a background actor fed by an `AsyncStream`; batched writes of 50 with a one-second partial-batch deadline ordered through the same stream, a failing batch gets 3 attempts with linear backoff (50 ms, 100 ms) before being dropped, and a 100,000-entry backpressure cap sheds the newest entries - every drop is surfaced through `droppedLogCount`)
- Integrates with OSLog for system-level logging
- Coordinates encryption and cleanup automatically

**Key protocols:**
- `LogRService` - public logging API (`@Observable`, `Sendable`). Logging (`log`/`debug`/`info`/…) and `init` are `nonisolated` (callable from any domain); conformers implement `record(level:message:…)`, and `log` and the level helpers are extension methods that fill in the call site (named apart so a 1.x `log(... String ...)` conformer fails to compile instead of inheriting a self-recursive default); the observable state that drives SwiftUI (`recentLogs`, `droppedLogCount`, `persistenceStatus`, `canAnalyseLogs`, AI results) is `@MainActor`
- `LogRPersistence` — storage abstraction (FileSystem or SQLite implementations)
- `LoggerCryptoServicing` - AES-256-GCM / ChaCha20-Poly1305 encryption with Keychain-backed keys. `LoggerCryptoService` writes a binary envelope (`0xC5`, format 2, cipher byte, big-endian `UInt32` key version, then the sealed box) around a JSON-encoded `LogEntry`, and still reads the 1.x JSON envelope (first byte `{`, `algorithm` optional = ChaCha). `SystemKeychainStore` calls the Security framework directly; on macOS it uses the data-protection keychain when the app is entitled (a provisioning profile) and the login keychain otherwise (`errSecMissingEntitlement`), copies keys Logr 1.x left in the login keychain on read, and removes from both. `swift test` binaries are not entitled, so tests use `InMemoryKeychainStore`
- `LogAIAnalyzer` — injectable analysis protocol; the native `AIAnalyzer` uses `FoundationModels` (26+) where `Package.swift` defines `LOGR_SYSTEM_MODEL` (iOS, macOS, Mac Catalyst, visionOS; also set on `LogrTests`) and reports unavailable elsewhere. Guard FoundationModels code with `#if LOGR_SYSTEM_MODEL`, never `canImport(FoundationModels)`: tvOS and watchOS SDKs ship the module without the system model

### Data Flow

Logging calls (nonisolated, any domain) → `LogR` (lock-protected in-memory cache) → `LogWriterActor` (background batching) → `LogRPersistence` (encrypted storage via `LoggerCryptoService`)

### Storage Options

- **FileSystemStorage** (actor): single append-only NDJSON file `Application Support/<bundle id>/Logr/logr_entries.ndjson` (one entry per line; the `Logr` directory is excluded from backups; a 1.3 file in `Documents` is moved on open, legacy JSON-array files are migrated oldest-first, an unterminated last line is cut, reads sort by timestamp, a failed append is rolled back), good for moderate volume
- **SQLiteStorage** (actor): system `SQLite3` database at `Application Support/<bundle id>/logs.sqlite`, WAL mode, schema unchanged from the 1.x GRDB version (its `grdb_migrations` table is left alone); the database and its `-wal`/`-shm` files are excluded from backups on every open

### Concurrency Model

- Logging (`init`, `log`, and the convenience methods) is `nonisolated` — callable from any isolation domain with no `await`. `LogR` is `@Observable` but not `@MainActor`; its `recentLogs` cache lives behind a `SafeMutex`, so synchronous read-after-write holds from any thread
- Only the `@Observable` state read by SwiftUI is `@MainActor` (`recentLogs`, `droppedLogCount`, `canAnalyseLogs`, the AI results + analysis methods); the change notification is coalesced and emitted on the main actor
- Background storage writes happen on dedicated `LogWriterActor`
- `LogrUI` target uses `@defaultIsolation(MainActor.self)`
- All three targets enable the `NonisolatedNonsendingByDefault` and `InferIsolatedConformances` upcoming features; `Logr` and `LogrTesting` also enable `ExistentialAny`, and `Logr` enables `ImmutableWeakCaptures`
- Logging methods use `@autoclosure` for lazy message evaluation

### Models

- **LogLevel**: debug, info, notice, warning, error, fault (with priority ordering)
- **LogCategory**: a `RawRepresentable` string struct with 49 predefined `static let`s; apps add their own (`static let checkout: Self = "checkout"` or a string literal). Encodes as a plain string and decodes the 1.x enum form (`{"network":{}}`, `{"custom":{"_0":"x"}}`). Deliberately not `CodingKeyRepresentable`, so `[LogCategory: LogLevel]` keeps the array encoding that 1.x configurations use
- **LogMessage** / **LogPrivacy**: `log()` takes a `LogMessage`, a string interpolation whose values each take a `privacy:` (default `.auto`, the OSLog rule: numbers and Bools public, the rest private); a `String` variable needs `LogMessage(text, privacy:)`. `LogR` keeps private values in clear only when `storesPrivateValues` (default `#if DEBUG`, which Xcode passes to package targets), never `.sensitive` ones. `.private(mask: .hash)` uses `LoggerCryptoServicing.privacyHashKey()`, read by the writer once the key is readable (`<private>` until then; memory-only loggers share a per-process random key). The OSLog mirror sends the redacted text as public and the private values as one private argument, through fixed templates (`OSLogMessage` cannot be built at run time)
- **LogEntry**: Immutable log record with source location, metadata, and category; `privateRanges` (UTF-8 offsets of private values stored in clear, encoded only when non-empty) are replaced by `<private>` in exports unless `includingPrivateValues: true`
- **EncryptedLogEntry**: Encrypted wrapper for persistent storage
- **LogrConfiguration**: Controls retention (max entries/age), cleanup interval (clamped to 60...86,400 s by both inits; NaN is the 1 h default), enabled levels, per-category overrides, verbosity, observation coalescing window (`coalesceWindowMillis`, default 100 ms), OSLog mirroring (`mirrorToOSLog`), private values in clear (`storesPrivateValues`)

### Testing

Tests use Swift Testing framework (`@Suite`, `@Test` attributes). The test target depends on `Logr`, `LogrUI` and `LogrTesting`. Real `LogR` tests back `LoggerCryptoService` with `InMemoryKeychainStore`, so no Keychain is touched; `LockableKeychainStore` (in `LoggerCryptoServiceTests.swift`) throws `errSecInteractionNotAllowed` until unlocked, and the internal `LogR(storage:cryptoService:configuration:analyser:retrySignals:)` / `LogWriterActor(retrySignals:)` let a test stand in for the protected-data notification. Tests that need disk hold a per-test `TemporaryDirectory` (removed on release); nothing writes to Documents or Application Support. `StorageConformanceTests` is the shared `LogRPersistence` contract, parameterized over both backends; the per-backend suites hold only backend-specific behaviour. `Tests/LogrTests/Fixtures/` holds files written by Logr 1.3 (key in `keychain.json`), read by `LegacyFixtureTests`: never regenerate them. Tests await events (`FlakyStorage.stores`, `Observations`), never the clock; `LogWriterActor(partialBatchDeadline:)` shortens the one-second deadline in tests. `MockLogR` in `Sources/LogrUI/Mock+Previews/` provides a full `LogRService` implementation for SwiftUI previews and unit tests with in-memory storage and sample data; its `log()` defers the insert to the main actor, so tests must hop to the main actor before reading `recentLogs`.

### Dependencies

- **swift-collections** (1.5.1+): Deque for log cache, the only dependency of the `Logr` target (SQLite and the Keychain come from the OS)
- **SwiftFormat** (0.61.0+): declared dependency, not a build plugin and not used for linting (that is the 0.63.1 CLI, see Code Formatting)
- **swift-docc-plugin** (1.5.0+): `swift package generate-documentation`
