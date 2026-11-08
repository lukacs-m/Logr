import Foundation
@testable import Logr
import LogrTesting
import Testing

@Suite("Issue digest")
struct LogIssueDigestTests {
    private static let start = Date(timeIntervalSince1970: 1_761_560_000)

    private static func entry(_ message: String, level: LogLevel = .error, category: LogCategory = .network,
                              file: String = "App/Sync.swift", line: Int = 10, at offset: TimeInterval = 0,
                              privateRanges: [Range<Int>] = []) -> LogEntry {
        LogEntry(timestamp: start.addingTimeInterval(offset), level: level, category: category, subsystem: "tests",
                 message: message, file: file, line: line, privateRanges: privateRanges)
    }

    private static func digest(_ entries: [LogEntry]) async -> LogIssueDigest {
        await LogIssueDigest.make(from: LogEntries(entries))
    }

    static let templates: [(String, String)] = [
        ("Request 42 failed after 1.5 s", "Request <number> failed after <number> s"),
        ("User 3F2504E0-4F89-41D3-9A0C-0305E82C3301 not found", "User <uuid> not found"),
        ("Bad pointer 0x7ffee4c0 freed", "Bad pointer <hex> freed"),
        ("Hash d7e08da1 mismatched", "Hash <hex> mismatched"),
        (#"Decoding "name" failed"#, "Decoding <string> failed"),
        (#"Quoted "42" and 7"#, "Quoted <string> and <number>"),
        ("Missing key 'id' in can't-parse payload", "Missing key <string> in can't-parse payload"),
        ("account <private:3f9a1c2e> locked", "account <private> locked"),
        ("Code -1009 for v2 API on HTTP/1.1 and base64", "Code <number> for v2 API on HTTP/<number> and base64"),
        ("Retry deadbeef added", "Retry deadbeef added")
    ]

    @Test(arguments: templates)
    func normalizesValues(message: String, template: String) {
        #expect(LogIssueDigest.template(for: message) == template)
    }

    @Test func groupsByCallSiteAndTemplate() async {
        let digest = await Self.digest([
            Self.entry("Request 3 failed", category: .database, at: 30),
            Self.entry("Request 2 failed", level: .fault, at: 20),
            Self.entry("Request 1 failed", level: .warning, at: 10),
            Self.entry("Request 1 failed", line: 11),
            Self.entry("Timeout after 3 s", at: 5),
            Self.entry("Fetched 3 items", level: .info),
            Self.entry("Cache miss", level: .notice),
            Self.entry("Tick", level: .debug)
        ])

        #expect(digest.groups.count == 3)
        let request = digest.groups[0]
        #expect(request.template == "Request <number> failed")
        #expect(request.count == 3)
        #expect(request.level == .fault)
        #expect(request.category == .database)
        #expect(request.firstSeen == Self.start.addingTimeInterval(10))
        #expect(request.lastSeen == Self.start.addingTimeInterval(30))
        #expect(request.sampleMessage == "Request 3 failed")
        #expect((digest.totalErrors, digest.totalWarnings, digest.totalFaults) == (3, 1, 1))
    }

    @Test func sortsBySeverityThenCountThenID() async {
        let digest = await Self.digest([
            Self.entry("warning", level: .warning, line: 1),
            Self.entry("warning", level: .warning, line: 1),
            Self.entry("warning", level: .warning, line: 1),
            Self.entry("error a", line: 2),
            Self.entry("error b", line: 3),
            Self.entry("error b", line: 3),
            Self.entry("error c", line: 4)
        ])

        #expect(digest.groups.first?.template == "error b")
        #expect(digest.groups.last?.template == "warning")
        let singles = digest.groups.filter { $0.level == .error && $0.count == 1 }
        #expect(singles.map(\.id) == singles.map(\.id).sorted())
    }

    @Test func idsAreStableAcrossRuns() async {
        let digest = await Self.digest([Self.entry("Request 7 failed"), Self.entry("Request 9 failed", at: 4)])
        // SHA-256 of "App/Sync.swift\0" + "10\0" + "Request <number> failed", first 8 bytes.
        #expect(digest.groups.map(\.id) == ["41be865cbdf0333e"])
    }

    @Test func masksPrivateValuesAndCutsLongSamples() async {
        let long = "Failed " + String(repeating: "x", count: 400)
        let digest = await Self.digest([
            Self.entry("Login failed for zoe@example.com", line: 1, privateRanges: [17..<32]),
            Self.entry(long, line: 2)
        ])

        let login = digest.groups.first { $0.line == 1 }
        #expect(login?.sampleMessage == "Login failed for <private>")
        #expect(login?.template == "Login failed for <private>")
        let cut = digest.groups.first { $0.line == 2 }
        #expect(cut?.sampleMessage.count == 300)
        #expect(cut?.sampleMessage.hasSuffix("…") == true)
    }

    @Test func noIssuesMakesAnEmptyDigest() async {
        #expect(await Self.digest([Self.entry("ok", level: .info)]) == .empty)
    }

    @Test func logRBuildsTheDigestFromRecentLogs() async {
        let logger = LogR(cryptoService: LoggerCryptoService(store: InMemoryKeychainStore()),
                          configuration: LogrConfiguration(mirrorToOSLog: false))
        for attempt in 1...3 {
            logger.error("Upload \(attempt) failed")
        }

        let digest = await logger.issueDigest()

        #expect(digest.groups.map(\.count) == [3])
        #expect(digest.groups.first?.template == "Upload <number> failed")
    }
}

@Suite("Issue summary assembly")
struct IssueSummaryAssemblyTests {
    private static func group(_ id: String, _ level: LogLevel, count: Int, category: LogCategory = .network,
                              line: Int = 1) -> LogIssueGroup {
        LogIssueGroup(id: id, level: level, category: category, file: "App/Sync.swift", line: line,
                      template: "template \(id)", count: count, firstSeen: .distantPast, lastSeen: .distantFuture,
                      sampleMessage: "sample \(id)")
    }

    private static let digest = LogIssueDigest(groups: [group("a", .fault, count: 2, line: 1),
                                                        group("b", .error, count: 40, line: 2),
                                                        group("c", .error, count: 3, category: .database, line: 3),
                                                        group("d", .warning, count: 7, line: 4)],
                                               totalErrors: 43, totalWarnings: 7, totalFaults: 2)

    private static func insight(_ index: Int, _ title: String, _ severity: LogSeverity = .low) -> LogIssueSummary.Insight {
        LogIssueSummary.Insight(groupIndex: index, title: title, explanation: "why \(title)", suggestedFix: "fix \(title)",
                                severity: severity)
    }

    @Test func insightsMapToTheirChunkGroups() {
        let chunk = Array(Self.digest.groups[1...2])
        let issues = LogIssueSummary.issues(from: [Self.insight(1, "C"), Self.insight(0, "B"), Self.insight(0, "B again"),
                                                   Self.insight(2, "out of range"), Self.insight(-1, "negative")],
                                            chunk: chunk)

        #expect(issues.mapValues(\.title) == ["b": "B", "c": "C"])
        #expect(issues["b"]?.group == chunk[0])
    }

    @Test func countsTotalsAndOrderComeFromTheDigest() {
        let issues = LogIssueSummary.issues(from: [Self.insight(0, "Crash", .critical), Self.insight(3, "Slow", .high)],
                                            chunk: Self.digest.groups)

        let summary = LogIssueSummary.assemble(digest: Self.digest, issues: issues,
                                               overview: ("All fine", ["Fix the crash"]))

        #expect(summary.issues.map(\.id) == ["a", "b", "c", "d"])
        #expect(summary.issues.map(\.group.count) == [2, 40, 3, 7])
        #expect(summary.issues.map(\.title) == ["Crash", "template b", "template c", "Slow"])
        #expect(summary.issues.map(\.severity) == [.critical, .high, .high, .high])
        #expect(summary.issues[1].explanation.isEmpty)
        #expect((summary.totalErrors, summary.totalWarnings, summary.totalFaults) == (43, 7, 2))
        #expect(summary.executiveSummary == "All fine")
        #expect(summary.priorityActions == ["Fix the crash"])
        #expect(summary.patterns == ["network: 3 issues, 49 entries"])
    }

    @Test func withoutAnOverviewTheSummaryIsCounts() {
        let summary = LogIssueSummary.assemble(digest: Self.digest, issues: [:], overview: nil)

        #expect(summary.executiveSummary == "43 errors, 7 warnings and 2 faults at 4 call sites.")
        #expect(summary.priorityActions == ["template a (App/Sync.swift:1, 2×)", "template b (App/Sync.swift:2, 40×)",
                                            "template c (App/Sync.swift:3, 3×)"])
        #expect(summary.issues.map(\.severity) == [.critical, .high, .high, .medium])
    }

    @Test @MainActor func logRPublishesTheAnalyzerResult() async throws {
        let analyzer = FakeAnalyzer()
        let logger = LogR(logAnalyser: analyzer, cryptoService: LoggerCryptoService(store: InMemoryKeychainStore()),
                          configuration: LogrConfiguration(mirrorToOSLog: false))
        logger.warning("Disk at 91%")
        for attempt in 1...2 {
            logger.error("Upload \(attempt) failed")
        }

        let summary = try await logger.summarizeIssues()

        #expect(summary.issues.map(\.title) == ["Upload <number> failed", "Disk at <number>%"])
        #expect(summary.issues.map(\.group.count) == [2, 1])
        #expect((summary.totalErrors, summary.totalWarnings) == (2, 1))
        #expect(logger.logIssueSummary == summary)
        #expect(logger.analysisProgress == nil)
        #expect(await analyzer.progress == [AnalysisProgress(totalGroups: 2, analyzedGroups: 2)])
    }

    @Test @MainActor func noIssuesSkipsTheAnalyzer() async throws {
        let logger = LogR(logAnalyser: FakeAnalyzer(failing: true),
                          cryptoService: LoggerCryptoService(store: InMemoryKeychainStore()),
                          configuration: LogrConfiguration(mirrorToOSLog: false))
        logger.info("All good")

        #expect(try await logger.summarizeIssues() == .empty)
    }

    @Test @MainActor func overlappingSummariesKeepTheNewest() async throws {
        let analyzer = HeldAnalyzer()
        let logger = LogR(logAnalyser: analyzer, cryptoService: LoggerCryptoService(store: InMemoryKeychainStore()),
                          configuration: LogrConfiguration(mirrorToOSLog: false))
        logger.error("Upload failed")
        let first = Task { try await logger.summarizeIssues() }
        while await !analyzer.isHolding(1) {
            await Task.yield()
        }
        let second = Task { try await logger.summarizeIssues() }
        while await !analyzer.isHolding(2) {
            await Task.yield()
        }

        await analyzer.release(1)
        let older = try await first.value

        // The older run does not clear the newer one's progress; its result stands until the newer one's.
        #expect(logger.analysisProgress == AnalysisProgress(totalGroups: 10, analyzedGroups: 2))
        #expect(logger.logIssueSummary == older)
        await analyzer.release(2)
        let newest = try await second.value
        #expect(logger.logIssueSummary == newest)
        #expect(logger.analysisProgress == nil)
    }

    @Test @MainActor func aFailedNewerSummaryLeavesTheOlderOnePublished() async throws {
        let analyzer = HeldAnalyzer()
        let logger = LogR(logAnalyser: analyzer, cryptoService: LoggerCryptoService(store: InMemoryKeychainStore()),
                          configuration: LogrConfiguration(mirrorToOSLog: false))
        logger.error("Upload failed")
        let first = Task { try await logger.summarizeIssues() }
        while await !analyzer.isHolding(1) {
            await Task.yield()
        }
        let second = Task { try await logger.summarizeIssues() }
        while await !analyzer.isHolding(2) {
            await Task.yield()
        }

        await analyzer.release(2, failing: true)
        await #expect(throws: HeldAnalyzer.Failure.self) { try await second.value }
        await analyzer.release(1)
        let older = try await first.value

        #expect(logger.logIssueSummary == older)
    }

    @Test @MainActor func anOlderSummaryDoesNotReplaceANewerOne() async throws {
        let analyzer = HeldAnalyzer()
        let logger = LogR(logAnalyser: analyzer, cryptoService: LoggerCryptoService(store: InMemoryKeychainStore()),
                          configuration: LogrConfiguration(mirrorToOSLog: false))
        logger.error("Upload failed")
        let first = Task { try await logger.summarizeIssues() }
        while await !analyzer.isHolding(1) {
            await Task.yield()
        }
        let second = Task { try await logger.summarizeIssues() }
        while await !analyzer.isHolding(2) {
            await Task.yield()
        }

        await analyzer.release(2)
        let newer = try await second.value
        await analyzer.release(1)
        _ = try await first.value

        #expect(logger.logIssueSummary == newer)
    }

    @Test @MainActor func aCancelledSummaryIsNotPublished() async throws {
        let analyzer = HeldAnalyzer()
        let logger = LogR(logAnalyser: analyzer, cryptoService: LoggerCryptoService(store: InMemoryKeychainStore()),
                          configuration: LogrConfiguration(mirrorToOSLog: false))
        logger.error("Upload failed")
        let summary = Task { try await logger.summarizeIssues() }
        while await !analyzer.isHolding(1) {
            await Task.yield()
        }

        summary.cancel()
        await analyzer.release(1)

        await #expect(throws: CancellationError.self) { try await summary.value }
        #expect(logger.logIssueSummary == nil)
    }

    @Test @MainActor func withoutAnAnalyzerSummariesThrow() async {
        let logger = LogR(cryptoService: LoggerCryptoService(store: InMemoryKeychainStore()),
                          configuration: LogrConfiguration(mirrorToOSLog: false))
        logger.error("Upload failed")

        #expect(!logger.canAnalyseLogs)
        await #expect(throws: AIAnalyzerError.self) { try await logger.summarizeIssues() }
    }
}

/// Titles each group with its template, the way a model's insights are merged.
private actor FakeAnalyzer: LogAIAnalyzer {
    struct Failure: Error {}
    let failing: Bool
    private(set) var progress: [AnalysisProgress] = []

    init(failing: Bool = false) {
        self.failing = failing
    }

    nonisolated var isAvailable: Bool {
        true
    }

    func summarizeIssues(_ digest: LogIssueDigest,
                         onProgress: @escaping @MainActor @Sendable (AnalysisProgress) -> Void) async throws
        -> LogIssueSummary {
        if failing { throw Failure() }
        let insights = digest.groups.indices.map {
            LogIssueSummary.Insight(groupIndex: $0, title: digest.groups[$0].template, explanation: "",
                                    suggestedFix: "", severity: .medium)
        }
        let done = AnalysisProgress(totalGroups: digest.groups.count, analyzedGroups: digest.groups.count)
        progress.append(done)
        await onProgress(done)
        return .assemble(digest: digest, issues: LogIssueSummary.issues(from: insights, chunk: digest.groups),
                         overview: nil)
    }
}

/// Holds each call until the test releases it; call `n` reports `n` groups explained, then all 10 once released.
private actor HeldAnalyzer: LogAIAnalyzer {
    struct Failure: Error {}
    private var calls = 0
    private var held: [Int: CheckedContinuation<Void, Never>] = [:]
    private var failing: Set<Int> = []

    nonisolated var isAvailable: Bool {
        true
    }

    func summarizeIssues(_ digest: LogIssueDigest,
                         onProgress: @escaping @MainActor @Sendable (AnalysisProgress) -> Void) async throws
        -> LogIssueSummary {
        calls += 1
        let call = calls
        await onProgress(AnalysisProgress(totalGroups: 10, analyzedGroups: call))
        await withCheckedContinuation { held[call] = $0 }
        if failing.contains(call) {
            throw Failure()
        }
        await onProgress(AnalysisProgress(totalGroups: 10, analyzedGroups: 10))
        return .assemble(digest: digest, issues: [:], overview: (executiveSummary: "run \(call)", priorityActions: []))
    }

    func isHolding(_ call: Int) -> Bool {
        held[call] != nil
    }

    func release(_ call: Int, failing: Bool = false) {
        if failing {
            self.failing.insert(call)
        }
        held.removeValue(forKey: call)?.resume()
    }
}
