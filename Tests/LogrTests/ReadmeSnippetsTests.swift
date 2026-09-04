//
//  ReadmeSnippetsTests.swift
//  Logr
//
//  Every ```swift block in README.md is reproduced below verbatim (blank lines, comments, imports
//  and `@main` aside — a test bundle cannot carry a `@main`), so a README example that no longer
//  compiles fails the build. `readmeSnippetsAreVerbatim` enforces the pairing. Snippets that would
//  touch the Keychain or disk are compile-only: private functions that are never called.
//

import Logr
import LogrUI
import SwiftUI
import Testing

// MARK: - Quick start

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

// MARK: - Configuration, storage, encryption, AI (compile-only)

private func configurationSnippet() throws {
    let config = LogrConfiguration(
        maxLogEntries: 5_000,
        maxLogAge: 24 * 60 * 60,
        enabledLevels: [.info, .warning, .error, .fault],
        categoryLevelOverrides: [.network: .warning],
        logVerbosity: .normal,
        mirrorToOSLog: false
    )
    let logger = try LogR(configuration: config)
    _ = logger
}

private func storageSnippet() throws {
    let sqlite = try LogR(storage: SQLiteStorage())      // Application Support/<bundle id>/logs.sqlite
    let file = try LogR(storage: FileSystemStorage())    // Documents/logr_entries.json, one JSON entry per line
    _ = (sqlite, file)
}

private func encryptionSnippet() throws {
    let crypto = try LoggerCryptoService(encryptionAlgo: .chacha)   // default is .aes256gcm
    let logger = try LogR(storage: SQLiteStorage(), cryptoService: crypto)
    try crypto.rotateKey()   // earlier entries stay readable unless removeOldKeys: true
    _ = logger
}

private func aiSnippet() throws {
    if #available(iOS 26.0, macOS 26.0, *) {
        let logger = try LogR(logAnalyser: AIAnalyzer())
        Task { @MainActor in
            let privacy = try await logger.scanForPrivacyIssues()
            let issues = try await logger.summarizeIssues()
            print(privacy.summary, issues.executiveSummary)
        }
    }
}

// MARK: - Testing

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

// MARK: - README ↔ this file

@Test func readmeSnippetsAreVerbatim() throws {
    let thisFile = URL(fileURLWithPath: #filePath)
    let packageRoot = thisFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let readme = try String(contentsOf: packageRoot.appendingPathComponent("README.md"), encoding: .utf8)
    let haystack = codeLines(of: try String(contentsOf: thisFile, encoding: .utf8))

    let blocks = readme.components(separatedBy: "```swift\n").dropFirst()
        .compactMap { $0.components(separatedBy: "\n```").first }
        .filter { !$0.hasPrefix("// Package.swift") }   // manifest fragment, not library code
    #expect(blocks.count >= 5)

    for block in blocks {
        #expect(haystack.contains(contiguous: codeLines(of: block)),
                "This README snippet is not reproduced verbatim in ReadmeSnippetsTests.swift:\n\(block)")
    }
}

/// Lines that take part in the comparison: trimmed, non-blank, and not a comment, an import or `@main`.
private func codeLines(of code: String) -> [String] {
    code.components(separatedBy: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("//") && !$0.hasPrefix("import ") && $0 != "@main" }
}

private extension [String] {
    func contains(contiguous other: [String]) -> Bool {
        guard !other.isEmpty, other.count <= count else { return false }
        return (0...(count - other.count)).contains { self[$0..<($0 + other.count)].elementsEqual(other) }
    }
}
