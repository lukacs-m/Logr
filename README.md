# LogR

[![Swift Package Manager Compatible](https://img.shields.io/badge/SPM-compatible-4BC51D.svg?style=flat)](https://swift.org/package-manager/)
[![Platform](https://img.shields.io/badge/platforms-iOS%2017.0%20%7C%20macOS%2014.0%20%7C%20tvOS%2017.0%20%7C%20watchOS%2010.0-333333.svg)](https://developer.apple.com/swift)
[![Swift](https://img.shields.io/badge/Swift-6.3-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Persistent, encrypted logging for Apple platforms, built on OSLog. Logs survive restarts, are
encrypted at rest with Keychain-backed keys, can be browsed in a drop-in SwiftUI viewer, and on
iOS 26+ can be analysed on-device by Apple Intelligence.

- **Log from anywhere**: logging is `nonisolated`, no `await`, safe from any actor or thread; persistence runs on a background actor
- **Two modules**: `Logr` (core) and `LogrUI` (viewer, statistics, mock)
- **Storage**: SQLite (recommended), an append-only NDJSON file, or your own `LogRPersistence`
- **Encryption**: AES-256-GCM or ChaCha20-Poly1305, versioned keys with rotation
- **Structure**: six levels, 49 predefined categories plus `.custom`, typed metadata on every entry

## Installation

Requires a Swift 6.3 toolchain. Platforms: iOS 17, macOS 14, tvOS 17, watchOS 10.
AI analysis needs iOS 26, macOS 26, tvOS 26 or watchOS 12.

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/lukacs-m/logr", from: "1.3.0")
]
```

Add `Logr` to your target, and `LogrUI` if you want the SwiftUI views. In Xcode: File → Add
Package Dependencies → `https://github.com/lukacs-m/logr`.

## Quick start

Create one `LogR` at the app root and inject it:

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
let logger = try LogR(configuration: config)
```

Every option and its default is documented on `LogrConfiguration`.

## Storage and encryption

`LogR()` alone keeps logs in memory and mirrors them to OSLog. Pass a storage to persist them:

```swift
let sqlite = try LogR(storage: SQLiteStorage())      // Application Support/<bundle id>/logs.sqlite
let file = try LogR(storage: FileSystemStorage())    // Documents/logr_entries.json, one JSON entry per line
```

Entries are encrypted before they reach storage. Pick the cipher or rotate the key through
`LoggerCryptoService`:

```swift
let crypto = try LoggerCryptoService(encryptionAlgo: .chacha)   // default is .aes256gcm
let logger = try LogR(storage: SQLiteStorage(), cryptoService: crypto)
try crypto.rotateKey()   // earlier entries stay readable unless removeOldKeys: true
```

Custom backends conform to `LogRPersistence`, custom encryption to `LoggerCryptoServicing`.
Both protocol docs carry a worked example. Opt-in `String` helpers such as `redactedEmail()`,
`maskedCreditCard()` and `hashed()` keep sensitive values out of messages.

## AI analysis (iOS 26+)

```swift
if #available(iOS 26.0, macOS 26.0, *) {
    let logger = try LogR(logAnalyser: AIAnalyzer())
    Task { @MainActor in
        let privacy = try await logger.scanForPrivacyIssues()
        let issues = try await logger.summarizeIssues()
        print(privacy.summary, issues.executiveSummary)
    }
}
```

Results are also published as `privacyAnalysisResult`, `logIssueSummary` and `analysisProgress`.
`LogViewer` shows an "Analyze logs" menu whenever `canAnalyseLogs` is true.

## Testing

`MockLogR` (in `LogrUI`) ships with 5,000 sample entries for previews and UI tests;
`MockLogR(empty: true)` starts blank. Its inserts hop to the main actor, so hop once before asserting.

The real `LogR` runs without Keychain or disk when the crypto service is backed by an in-memory store:

```swift
final class InMemoryKeychain: KeychainStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    func data(forKey key: String) throws -> Data? { lock.withLock { storage[key] } }
    func set(_ data: Data, forKey key: String) throws { lock.withLock { storage[key] = data } }
    func remove(forKey key: String) throws { lock.withLock { _ = storage.removeValue(forKey: key) } }
}

@Test func logsAreCachedSynchronously() throws {
    let crypto = try LoggerCryptoService(store: InMemoryKeychain())
    let logr = LogR(cryptoService: crypto)   // no storage: nothing is persisted, and this init does not throw

    logr.info("hello", category: .test)

    #expect(logr.recentLogs.first?.message == "hello")   // nonisolated read on the concrete LogR, no hop
}
```

## Code map

Data flow: `log()` → lock-protected cache (and OSLog) → `LogWriterActor` → `LoggerCryptoServicing` → `LogRPersistence`.

| Path | What lives there |
|---|---|
| `Sources/Logr/LogR.swift` | `LogR`: the cache, coalesced observation, the cleanup timer, and the private `LogWriterActor` (encrypt → batch of 50 → store; 3 attempts with backoff; 100,000-entry backpressure cap, every drop counted in `droppedLogCount`) |
| `Sources/Logr/Protocols/` | `LogRService` (public API plus `getLogs`, `exportLogs`, `logStatistics`), `LogRPersistence`, `LogAIAnalyzer` |
| `Sources/Logr/Models/` | `LogEntry`, `LogLevel`, `LogCategory`, `LogMetadataValue`, `LogrConfiguration`, `LogStatistics`, `ExportFormat`, AI result types, errors |
| `Sources/Logr/Tools/` | `LoggerCryptoService` and `KeychainStore`, `FileSystemStorage`, `SQLiteStorage`, `SafeMutex` |
| `Sources/Logr/Utilities/` | `String` redaction helpers |
| `Sources/Logr/AI/` | `AIAnalyzer`: FoundationModels, chunked and parallel, iOS 26+ |
| `Sources/LogrUI/LogViews/` | `LogViewer`, its filter and export sheets, the entry row |
| `Sources/LogrUI/Statistics/` | `LogStatisticsView`, `CompactLogStatisticsView` |
| `Sources/LogrUI/AIAnalysisViews/` | Privacy warnings, issue summary and progress views |
| `Sources/LogrUI/Mock+Previews/` | `MockLogR` |
| `Sources/LogrUI/Tools+Extensions/` | The `\.logService` environment key, `.logRService(_:)`, the no-op default logger, level and severity colours |
| `Tests/LogrTests/` | Swift Testing suites; `ReadmeSnippetsTests.swift` compiles every snippet in this file |
| `LogRExample/` | Xcode sample app exercising every feature |

## Documentation

- **API reference**: [lukacs-m.github.io/Logr](https://lukacs-m.github.io/Logr/), generated by DocC from the doc comments on every public symbol. Locally: `swift package generate-documentation --target Logr`
- **Snippets**: every Swift block in this README is compiled and checked verbatim by `Tests/LogrTests/ReadmeSnippetsTests.swift`
- **Issues**: [github.com/lukacs-m/logr/issues](https://github.com/lukacs-m/logr/issues)

## License

MIT. See [LICENSE](LICENSE).
