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
import LogrTesting
import LogrUI
import SwiftUI
import Testing

// MARK: - Quick start

struct MyApp: App {
    @State private var logger = LogR(storage: .sqlite())

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

private func configurationSnippet() {
    let config = LogrConfiguration(
        maxLogEntries: 5_000,
        maxLogAge: 24 * 60 * 60,
        enabledLevels: [.info, .warning, .error, .fault],
        categoryLevelOverrides: [.network: .warning],
        logVerbosity: .normal,
        mirrorToOSLog: false
    )
    let logger = LogR(configuration: config)
    _ = logger
}

private func storageSnippet() {
    let sqlite = LogR(storage: .sqlite())    // Application Support/<bundle id>/logs.sqlite
    let file = LogR(storage: .file())        // Application Support/<bundle id>/Logr/logr_entries.ndjson
    _ = (sqlite, file)
}

private func encryptionSnippet() throws {
    let crypto = LoggerCryptoService(encryptionAlgo: .chacha)   // default is .aes256gcm
    let logger = LogR(storage: .sqlite(), cryptoService: crypto)
    try crypto.rotateKey()   // earlier entries stay readable unless removeOldKeys: true
    _ = logger
}

private func aiSnippet() {
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
}

// MARK: - Testing

@Test func logsAreCachedSynchronously() {
    let crypto = LoggerCryptoService(store: InMemoryKeychainStore())
    let logr = LogR(cryptoService: crypto)   // no storage: nothing is persisted

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
