# LogR

[![Swift Package Manager Compatible](https://img.shields.io/badge/SPM-compatible-4BC51D.svg?style=flat)](https://swift.org/package-manager/)
[![Platform](https://img.shields.io/badge/platforms-iOS%2017.0%20%7C%20macOS%2014.0%20%7C%20tvOS%2017.0%20%7C%20watchOS%2010.0-333333.svg)](https://developer.apple.com/swift)
[![Swift](https://img.shields.io/badge/Swift-6.3-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Persistent, encrypted logging for Apple platforms, built on OSLog. Logs survive restarts, are
encrypted at rest with Keychain-backed keys, can be browsed in a drop-in SwiftUI viewer, and on
iOS 26+ can be analysed on-device by Apple Intelligence.

- **Log from anywhere**: logging is `nonisolated`, no `await`, safe from any actor or thread; persistence runs on a background actor
- **Three modules**: `Logr` (core), `LogrUI` (viewer, statistics, mock) and `LogrTesting` (test doubles)
- **Storage**: SQLite, an append-only NDJSON file, or your own `LogRPersistence`
- **Encryption**: AES-256-GCM or ChaCha20-Poly1305, versioned keys with rotation
- **Structure**: six levels, 49 predefined categories plus your own (`static let checkout: LogCategory = "checkout"`), typed metadata on every entry

## Installation

Requires a Swift 6.3 toolchain. Platforms: iOS 17, macOS 14, tvOS 17, watchOS 10.
Native AI analysis needs iOS 26 or macOS 26 and an available Apple Intelligence model.
On tvOS and watchOS, core logging remains available and the native analyzer reports unavailable.
The native file exporter is available on iOS and macOS.

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/lukacs-m/logr", from: "1.3.0")
]
```

Add `Logr` to your target, `LogrUI` if you want the SwiftUI views, and `LogrTesting` to your test
target. In Xcode: File → Add Package Dependencies → `https://github.com/lukacs-m/logr`.

## Quick start

Create one `LogR` at the app root and inject it:

```swift
import Logr
import LogrUI
import SwiftUI

@main
struct MyApp: App {
    @State private var logger = LogR(storage: .sqlite())

    var body: some Scene {
        WindowGroup {
            ContentView()
                .logRService(logger)
        }
    }
}
```

Log from views through the environment, and drop in the viewer:

```swift
struct ContentView: View {
    @Environment(\.logService) private var logger

    var body: some View {
        NavigationStack {
            VStack {
                Button("Log something") {
                    logger.info("Button tapped", category: .ui, metadata: ["screen": "home"])
                }
                NavigationLink("Logs") { LogViewer() }   // LogViewer needs a NavigationStack around it
            }
        }
    }
}
```

Log from any isolation domain, with no `await` and no main-thread hop:

```swift
actor SyncEngine {
    let logger: any LogRService

    init(logger: any LogRService) {
        self.logger = logger
    }

    func sync() {
        logger.notice("Sync started", category: .sync)   // no await: logging is synchronous
    }
}

@concurrent
func processImages(logger: any LogRService) async {
    logger.warning("Image processing is slow", category: .performance)
}
```

Through `any LogRService`, `recentLogs` and the other observable properties are `@MainActor`.
On the concrete `LogR` they are `nonisolated`, and a read right after a write sees the entry.
SwiftUI change notifications are coalesced (`coalesceWindowMillis`, default 100 ms).

## Privacy

Each interpolated value carries a privacy level, as in OSLog. Strings and other values are private by
default; integers, floating-point numbers and Booleans are public:

```swift
func signIn(email: String, attempts: Int, token: String, logger: any LogRService) {
    logger.info("Signed in \(email) after \(attempts) tries", category: .authentication)
    // Release builds store "Signed in <private> after 3 tries"
    logger.info("Account \(email, privacy: .private(mask: .hash))", category: .user)
    // "Account <private:3f9a1c2e>": equal values give equal hashes
    logger.debug("Token \(token, privacy: .sensitive)", category: .authentication)
    // "Token <sensitive>", even in DEBUG builds
}
```

`LogR` keeps private values in clear in `DEBUG` builds so you can read them while developing, and stores
`<private>` otherwise (`LogrConfiguration.storesPrivateValues`). Exports replace them with `<private>`
unless you pass `exportLogs(format:includingPrivateValues: true)`. The OSLog mirror logs the redacted text
as public and the private values after it as private, so Console shows them only while a debugger is
attached or private data logging is enabled. A `String` you already hold needs a privacy of its own:
`LogMessage(text, privacy: .public)`.

## Context

With `LogR`, metadata set with `LogContext.with` reaches every entry logged inside the scope, including from
child tasks:

```swift
func checkout(orderID: String, logger: any LogRService) async {
    await LogContext.with(["orderID": .string(orderID)]) {
        logger.info("Checkout started", category: .payment)   // carries orderID
        await withTaskGroup(of: Void.self) { group in
            group.addTask { logger.info("Charging card", category: .payment) }   // so does a child task
        }
    }
}
```

Nested scopes merge, and metadata passed to the call wins on a key clash. `Task.detached` does not inherit the
context.

## Configuration

```swift
let config = LogrConfiguration(
    maxLogEntries: 5_000,
    maxLogAge: 24 * 60 * 60,
    enabledLevels: [.info, .warning, .error, .fault],
    categoryLevelOverrides: [.network: .warning],
    logVerbosity: .normal,
    mirrorToOSLog: false
)
let logger = LogR(configuration: config)
```

Every option and its default is documented on `LogrConfiguration`.

## Storage and encryption

`LogR()` alone keeps logs in memory and mirrors them to OSLog. Pass a storage to persist them.
Partial batches are submitted after one second; call `await logger.flush()` before a lifecycle
transition when you need pending writes processed immediately:

```swift
let sqlite = LogR(storage: .sqlite())    // Application Support/<bundle id>/logs.sqlite
let file = LogR(storage: .file())        // Application Support/<bundle id>/Logr/logr_entries.ndjson
```

Pass a file URL to either to choose the location, or `.custom(_:)` with your own `LogRPersistence`.
Storage opens in the background, so creating a logger never throws. Until the key and the storage can be
read (before the device's first unlock after a restart, during a background launch), entries wait in
memory, `persistenceStatus` is `.waitingForProtectedData`, and they are written once both can be read.

Both keep the same window: the newest `maxLogEntries` entries younger than `maxLogAge`. They differ in
cleanup: SQLite deletes expired rows in place, while the file storage, which writes one JSON entry per
line, rewrites the whole file. Both default locations are excluded from backups: entries are encrypted
with a key that never leaves the device. A file Logr 1.3 or earlier left in `Documents` is moved to
Application Support on first open.

Entries are encrypted before they reach storage, with keys kept in the Keychain by `SystemKeychainStore`
(on macOS: the data-protection keychain when the app has a provisioning profile, the login keychain
otherwise). Pick the cipher or rotate the key through `LoggerCryptoService`:

```swift
let crypto = LoggerCryptoService(encryptionAlgo: .chacha)   // default is .aes256gcm
let logger = LogR(storage: .sqlite(), cryptoService: crypto)
try crypto.rotateKey()   // earlier entries stay readable unless removeOldKeys: true
```

Custom backends conform to `LogRPersistence`, custom encryption to `LoggerCryptoServicing`.
Both protocol docs carry a worked example. Opt-in `String` helpers such as `redactedEmail()`,
`maskedCreditCard()` and `hashed()` keep sensitive values out of messages.

## AI analysis (iOS 26+)

```swift
if #available(iOS 26.0, macOS 26.0, *) {
    let logger = LogR(logAnalyser: AIAnalyzer())
    Task { @MainActor in
        do {
            let privacy = try await logger.scanForPrivacyIssues()
            let issues = try await logger.summarizeIssues()
            print(privacy.summary, issues.executiveSummary)
        } catch {
            print("Analysis failed: \(error)")
        }
    }
}
```

Results are also published as `privacyAnalysisResult`, `logIssueSummary` and `analysisProgress`.
`LogViewer` shows an "Analyze logs" menu whenever `canAnalyseLogs` is true.

## Testing

`MockLogR` (in `LogrUI`) ships with 5,000 sample entries for previews and UI tests;
`MockLogR(empty: true)` starts blank. Its inserts hop to the main actor, so hop once before asserting.

The real `LogR` runs without Keychain or disk when the crypto service is backed by
`InMemoryKeychainStore`, from the `LogrTesting` product:

```swift
import Logr
import LogrTesting
import Testing

@Test func logsAreCachedSynchronously() {
    let crypto = LoggerCryptoService(store: InMemoryKeychainStore())
    let logr = LogR(cryptoService: crypto)   // no storage: nothing is persisted

    logr.info("hello", category: .test)

    #expect(logr.recentLogs.first?.message == "hello")   // nonisolated read on the concrete LogR, no hop
}
```

## Code map

Data flow: `log()` → lock-protected cache (and OSLog) → `LogWriterActor` → `LoggerCryptoServicing` → `LogRPersistence`.

| Path | What lives there |
|---|---|
| `Sources/Logr/LogR.swift` | `LogR`: the cache, coalesced observation, the cleanup timer, and the private `LogWriterActor` (opens the storage in the background and holds entries while the key or storage cannot be read; encrypt → batch of 50 or one-second partial-batch deadline → store; 3 attempts with backoff; 100,000-entry backpressure cap, every drop counted in `droppedLogCount`) |
| `Sources/Logr/Protocols/` | `LogRService` (public API plus `getLogs`, `exportLogs`, `logStatistics`), `LogRPersistence`, `LogAIAnalyzer` |
| `Sources/Logr/Models/` | `LogEntry`, `LogEntries`, `LogMessage`, `LogPrivacy`, `LogContext`, `LogLevel`, `LogCategory`, `LogMetadataValue`, `LogStorage`, `PersistenceStatus`, `LogrConfiguration`, `LogStatistics`, `ExportFormat`, AI result types, errors |
| `Sources/Logr/Tools/` | `LoggerCryptoService`, `KeychainStore` and `SystemKeychainStore`, `FileSystemStorage`, `SQLiteStorage`, `SafeMutex` |
| `Sources/Logr/Utilities/` | `String` redaction helpers |
| `Sources/Logr/AI/` | `AIAnalyzer`: FoundationModels, chunked and parallel, iOS 26+ |
| `Sources/LogrUI/LogViews/` | `LogViewer`, its filter and export sheets, the entry row |
| `Sources/LogrUI/Statistics/` | `LogStatisticsView`, `CompactLogStatisticsView` |
| `Sources/LogrUI/AIAnalysisViews/` | Privacy warnings, issue summary and progress views |
| `Sources/LogrUI/Mock+Previews/` | `MockLogR` |
| `Sources/LogrUI/Tools+Extensions/` | The `\.logService` environment key, `.logRService(_:)`, the no-op default logger, level and severity colours |
| `Sources/LogrTesting/` | `InMemoryKeychainStore` |
| `Tests/LogrTests/` | Swift Testing suites; `ReadmeSnippetsTests.swift` compiles every snippet in this file |
| `LogRExample/` | Xcode sample app exercising every feature |

## Documentation

- **API reference**: [lukacs-m.github.io/Logr](https://lukacs-m.github.io/Logr/), generated by DocC from the doc comments on every public symbol. Locally: `swift package generate-documentation --target Logr`
- **Snippets**: every Swift block in this README is compiled and checked verbatim by `Tests/LogrTests/ReadmeSnippetsTests.swift`
- **Issues**: [github.com/lukacs-m/logr/issues](https://github.com/lukacs-m/logr/issues)

## License

MIT. See [LICENSE](LICENSE).
