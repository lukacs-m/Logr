//
//  MockLogR.swift
//  Logr
//
//  Created by Martin Lukacs on 16/11/2025.
//

import DequeModule
import Foundation
import Logr

// MARK: - Mock Implementation

public enum GenerationMode {
    case instant // Generate all at once
    case stream(chunks: Int, delay: TimeInterval) // Stream in chunks
}

public struct GenerationConfig {
    public let totalEntries: Int
    public let timeRange: TimeInterval // How far back in time to start
    public let levelDistribution: [LogLevel: Double] // Probability for each level (0.0-1.0)
    public let categories: [LogCategory]
    public let subsystems: [String]

    public init(totalEntries: Int = 5_000,
                timeRange: TimeInterval = 86_400, // 24 hours
                levelDistribution: [LogLevel: Double] = [
                    .debug: 0.4,
                    .info: 0.3,
                    .notice: 0.15,
                    .error: 0.1,
                    .fault: 0.05
                ],
                categories: [LogCategory] = [
                    .system, .network, .ui, .authentication,
                    .database, .performance,
                    "business-logic",
                    "analytics"
                ],
                subsystems: [String] = [
                    "com.logr.main",
                    "com.logr.networking",
                    "com.logr.database",
                    "com.logr.ui",
                    "com.logr.analytics"
                ]) {
        self.totalEntries = totalEntries
        self.timeRange = timeRange
        self.levelDistribution = levelDistribution
        self.categories = categories
        self.subsystems = subsystems
    }
}

@Observable
public final class MockLogR: LogRService, Sendable {
    public var privacyAnalysisResult: PrivacyAnalysisResult? {
        Self.samplePrivacyResult
    }

    public var logIssueSummary: LogIssueSummary? {
        Self.sampleIssueSummary
    }

    public var analysisProgress: AnalysisProgress? {
        nil
    }

    @MainActor public var canAnalyseLogs: Bool = true

    @MainActor public var droppedLogCount = 0

    @MainActor public var recentLogs: LogEntries {
        LogEntries(cachedLogs)
    }

    @MainActor private var cachedLogs = Deque<LogEntry>()
    @MainActor public private(set) var isCleanupRunning = false

    @MainActor private var mockLogs = Deque<LogEntry>()

    @MainActor
    public init(empty: Bool = false,
                config: GenerationConfig = GenerationConfig(),
                mode: GenerationMode = .instant) {
        if !empty {
            switch mode {
            case .instant:
                generateMockData(config: config)
            case let .stream(chunks, delay):
                // For streaming, start with empty and stream in data
                Task {
                    await streamMockData(config: config, chunks: chunks, delay: delay)
                }
            }
        }
    }

    // MARK: - LogRService Implementation

    public nonisolated func record(level: LogLevel,
                                   message: @autoclosure () -> LogMessage,
                                   category: LogCategory,
                                   file: String,
                                   function: String,
                                   line: Int,
                                   metadata: @autoclosure () -> [String: LogMetadataValue]?) {
        // Evaluate the message synchronously (preserving lazy semantics), then hop the insert to
        // the main actor where the observable cache lives.
        //
        // NOTE: unlike `LogR`, this insert is *deferred*. `recentLogs` is not updated before
        // `log()` returns (no synchronous read-after-write), and because separate `Task`s are not
        // guaranteed to run in enqueue order, entries logged in a tight burst may be inserted out
        // of order. That is fine for the previews/sample data this mock exists for; a test that
        // asserts on `recentLogs` right after `log()` must first hop to the main actor (e.g.
        // `await Task { @MainActor in }.value`) to observe the entry.
        let rendered = message().rendered(keepingPrivateValues: LogrConfiguration.default.storesPrivateValues,
                                          hashKey: nil)
        let entry = LogEntry(level: level,
                             category: category,
                             subsystem: "com.logr.mock",
                             message: rendered.text,
                             file: file,
                             function: function,
                             line: line,
                             metadata: metadata(),
                             privateRanges: rendered.privateRanges)
        Task { @MainActor in append(entry) }
    }

    @MainActor
    private func append(_ entry: LogEntry) {
        mockLogs.insert(entry, at: 0)
        cachedLogs.insert(entry, at: 0)

        // Keep only the most recent 100 entries for demo
        if mockLogs.count > 100 {
            mockLogs.removeLast()
        }
        if cachedLogs.count > 100 {
            cachedLogs.removeLast()
        }
    }

    @MainActor
    public func clearLogs() async throws {
        mockLogs.removeAll()
        cachedLogs.removeAll()
    }

    public func flush() async {}

    public func scanForPrivacyIssues(detectors: [PrivacyDetector]) async -> PrivacyAnalysisResult {
        Self.samplePrivacyResult
    }

    public func summarizeIssues() async throws -> LogIssueSummary {
        Self.sampleIssueSummary
    }

    private static let samplePrivacyResult = PrivacyAnalysisResult(warnings: [
        PrivacyWarning(file: "Payments/PaymentService.swift", line: 158, detector: "Payment card",
                       severity: .critical, occurrences: 3,
                       excerpt: "Charging [Payment card] for order 1042", field: "message"),
        PrivacyWarning(file: "Auth/LoginViewController.swift", line: 42, detector: "Email address",
                       severity: .high, occurrences: 12,
                       excerpt: "Signed in as [Email address]", field: "message"),
        PrivacyWarning(file: "Sync/SyncClient.swift", line: 77, detector: "IP address", severity: .medium,
                       occurrences: 1, excerpt: "peer=[IP address]", field: "peer")
    ],
    summary: "3 call sites log sensitive values: 1 critical, 1 high severity.",
    criticalCount: 1,
    highCount: 1)

    private static let sampleIssueSummary: LogIssueSummary = {
        func group(_ id: String, _ level: LogLevel, _ category: LogCategory, _ file: String, _ line: Int,
                   _ template: String, _ count: Int) -> LogIssueGroup {
            LogIssueGroup(id: id, level: level, category: category, file: file, line: line, template: template,
                          count: count, firstSeen: .now.addingTimeInterval(-3_600), lastSeen: .now,
                          sampleMessage: template.replacingOccurrences(of: "<number>", with: "30"))
        }
        return LogIssueSummary(executiveSummary: "Network timeouts and a recurring crash dominate the recent errors. "
            + "Fix the force unwrap in the parser first, then add retries to API requests.",
            issues: [
                LogIssue(group: group("6f1c2a9b0d3e4f51", .fault, .database,
                                      "Data/DataParser.swift", 89,
                                      "Unexpectedly found nil while decoding <string>", 5),
                         title: "Force unwrap causing crashes",
                         explanation: "An optional value is force unwrapped without a check.",
                         suggestedFix: "Use optional binding or a default value instead of a force unwrap.",
                         severity: .critical),
                LogIssue(group: group("0a7e3c5d9b1f2468", .error, .network,
                                      "Network/NetworkManager.swift", 156,
                                      "Request timed out after <number> s", 23),
                         title: "Network timeout in API requests",
                         explanation: "API requests time out after 30 seconds.",
                         suggestedFix: "Retry with exponential backoff and lower the timeout to 15 s.",
                         severity: .high),
                LogIssue(group: group("c4b2e8f0a6d1937e", .warning, .performance,
                                      "UI/ImageProcessor.swift", 234,
                                      "Image processing took <number> ms on the main thread",
                                      12),
                         title: "Main thread blocked by image processing",
                         explanation: "Image processing runs on the main thread and freezes the UI.",
                         suggestedFix: "Move image processing to a background task.",
                         severity: .medium)
            ],
            totalErrors: 23,
            totalWarnings: 12,
            totalFaults: 5,
            patterns: ["network: 2 issues, 31 entries"],
            priorityActions: [
                "Replace the force unwrap in the data parser",
                "Add retries with backoff to API requests"
            ])
    }()

    // MARK: - Instant Generation

    @MainActor
    private func generateMockData(config: GenerationConfig) {
        let now = Date()
        let totalProbability = config.levelDistribution.values.reduce(0, +)

        // Pre-allocate array for better performance
        var entries = Deque<LogEntry>()
        entries.reserveCapacity(config.totalEntries)

        for i in 0..<config.totalEntries {
            let timestamp = now
                .addingTimeInterval(-config
                    .timeRange + (config.timeRange * Double(i) / Double(config.totalEntries)))

            let level = selectLevel(from: config.levelDistribution, totalProbability: totalProbability)
            let category = config.categories.randomElement() ?? .system
            let subsystem = config.subsystems.randomElement() ?? "com.logr.example"
            let message = generateMessage(for: level, category: category, index: i)

            entries.append(LogEntry(timestamp: timestamp,
                                    level: level,
                                    category: category,
                                    subsystem: subsystem,
                                    message: message))
        }

        // Batch update for better Observable performance
        mockLogs = entries
        cachedLogs = entries
    }

    // MARK: - Streaming Generation

    @MainActor
    private func streamMockData(config: GenerationConfig, chunks: Int, delay: TimeInterval) async {
        let now = Date()
        let totalProbability = config.levelDistribution.values.reduce(0, +)
        let entriesPerChunk = config.totalEntries / chunks

        for chunk in 0..<chunks {
            var entries: [LogEntry] = []
            entries.reserveCapacity(entriesPerChunk)

            let startIndex = chunk * entriesPerChunk
            let endIndex = min(startIndex + entriesPerChunk, config.totalEntries)

            for i in startIndex..<endIndex {
                let timestamp = now
                    .addingTimeInterval(-config
                        .timeRange + (config.timeRange * Double(i) / Double(config.totalEntries)))

                let level = selectLevel(from: config.levelDistribution, totalProbability: totalProbability)
                let category = config.categories.randomElement() ?? .system
                let subsystem = config.subsystems.randomElement() ?? "com.logr.example"
                let message = generateMessage(for: level, category: category, index: i)

                entries.append(LogEntry(timestamp: timestamp,
                                        level: level,
                                        category: category,
                                        subsystem: subsystem,
                                        message: message))
            }

            // Update on main actor in batches
            mockLogs.append(contentsOf: entries)
            cachedLogs.append(contentsOf: entries)

            if chunk < chunks - 1 {
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    private func generateMessage(for level: LogLevel, category: LogCategory, index: Int) -> String {
        let categoryName = category.displayName

        switch level {
        case .debug:
            return [
                "\(categoryName) operation step \(index % 100) completed",
                "\(categoryName) cache updated with \(index) items",
                "\(categoryName) state changed to active",
                "\(categoryName) configuration loaded successfully"
            ].randomElement()!

        case .info:
            return [
                "\(categoryName) processing started at \(Date())",
                "\(categoryName) received data packet #\(index)",
                "\(categoryName) user action recorded",
                "System status: \(categoryName) is operational"
            ].randomElement()!

        case .notice:
            return [
                "\(categoryName) performance threshold reached: \(index)ms",
                "\(categoryName) configuration updated",
                "\(categoryName) entering maintenance mode",
                "\(categoryName) quota at 75% capacity"
            ].randomElement()!

        case .error:
            return [
                "\(categoryName) failed to process request #\(index): timeout",
                "\(categoryName) authentication failed for user_\(index)",
                "\(categoryName) data validation error at step \(index % 50)",
                "\(categoryName) connection lost to service"
            ].randomElement()!

        case .fault:
            return [
                "\(categoryName) critical failure: unrecoverable error",
                "\(categoryName) system crash detected at address 0x\(String(index, radix: 16))",
                "\(categoryName) data corruption detected in block \(index)",
                "\(categoryName) service unavailable - immediate attention required"
            ].randomElement()!

        default:
            return "Unknown"
        }
    }

    // MARK: - Helpers

    private func selectLevel(from distribution: [LogLevel: Double], totalProbability: Double) -> LogLevel {
        let random = Double.random(in: 0...totalProbability)
        var cumulative = 0.0

        for (level, probability) in distribution.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            cumulative += probability
            if random <= cumulative {
                return level
            }
        }

        return .info // Fallback
    }
}

//// MARK: - Usage Examples
//
//// Generate 5,000 entries instantly (default config)
// let mockService = MockLogR(empty: false)
//
//// Generate 50,000 entries with custom config
// let heavyConfig = GenerationConfig(
//    totalEntries: 50_000,
//    timeRange: 604800, // 7 days
//    levelDistribution: [
//        .debug: 0.5,
//        .info: 0.25,
//        .notice: 0.15,
//        .error: 0.08,
//        .fault: 0.02
//    ]
// )
// let heavyMockService = MockLogR(config: heavyConfig)
//
//// Stream 100,000 entries in chunks for simulated real-time updates
// let streamingService = MockLogR(
//    config: GenerationConfig(totalEntries: 100_000),
//    mode: .stream(chunks: 100, delay: 0.1)
// )
