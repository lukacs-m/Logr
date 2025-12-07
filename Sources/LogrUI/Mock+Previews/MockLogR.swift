//
//  MockLogR.swift
//  Logr
//
//  Created by Martin Lukacs on 16/11/2025.
//

import Collections
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
                    .custom("business-logic"),
                    .custom("analytics")
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
@MainActor
public final class MockLogR: LogRService, Sendable {
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    public var privacyAnalysisResult: PrivacyAnalysisResult? {
        PrivacyAnalysisResult(warnings: [
            PrivacyWarning(file: "LoginViewController.swift",
                           line: 42,
                           exposureType: "email",
                           exposedContent: "user@example.com",
                           explanation: "Email address is being logged in plain text, which could expose user identity.",
                           severity: .high,
                           recommendation: "Remove email logging or use hashed/redacted versions."),
            PrivacyWarning(file: "PaymentService.swift",
                           line: 158,
                           exposureType: "credit card",
                           exposedContent: "4532-1234-5678-1234",
                           explanation: "Full credit card number detected in logs - severe PCI compliance violation.",
                           severity: .critical,
                           recommendation: "Never log credit card numbers. Implement PCI-DSS compliant logging.")
        ],
        summary: "Found 2 potential privacy exposures: 1 critical, 1 high severity.",
        criticalCount: 1,
        highCount: 1)
    }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    public var logIssueSummary: LogIssueSummary? {
        LogIssueSummary(executiveSummary: "Analyzed 45 errors, 23 warnings, and 3 faults. Found 12 distinct issues: 2 critical, 4 high severity. Immediate action required on critical issues.",
                        issues: [
                            LogIssue(category: "error",
                                     title: "Network timeout in API requests",
                                     description: "Multiple API requests are timing out after 30 seconds, causing poor user experience.",
                                     file: "NetworkManager.swift",
                                     line: 156,
                                     occurrences: 23,
                                     severity: .high,
                                     suggestedFix: "Implement retry logic with exponential backoff and reduce timeout to 15s."),
                            LogIssue(category: "crash",
                                     title: "Force unwrap causing crashes",
                                     description: "Optional value is being force unwrapped without safety checks, leading to runtime crashes.",
                                     file: "DataParser.swift",
                                     line: 89,
                                     occurrences: 5,
                                     severity: .critical,
                                     suggestedFix: "Use optional binding (if let) or nil coalescing instead of force unwrap."),
                            LogIssue(category: "performance",
                                     title: "Main thread blocked by heavy computation",
                                     description: "Image processing is running on main thread causing UI freezes.",
                                     file: "ImageProcessor.swift",
                                     line: 234,
                                     occurrences: 12,
                                     severity: .medium,
                                     suggestedFix: "Move image processing to background queue using DispatchQueue.global().")
                        ],
                        totalErrors: 45,
                        totalWarnings: 23,
                        totalFaults: 3,
                        patterns: [
                            "3 error issues detected across multiple locations",
                            "High frequency of network-related errors during peak hours",
                            "Memory warnings correlate with image processing operations"
                        ],
                        priorityActions: [
                            "Force unwrap causing crashes (DataParser.swift:89)",
                            "Network timeout in API requests (NetworkManager.swift:156)",
                            "Memory leak in cache manager (CacheManager.swift:201)"
                        ])
    }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    public var analysisProgress: AnalysisProgress? {
        nil
    }

    public var canAnalyseLogs: Bool = true

    public private(set) var recentLogs = Deque<LogEntry>()
    public private(set) var isCleanupRunning = false

    private var mockLogs = Deque<LogEntry>()

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

    public func log(level: LogLevel,
                    message: @autoclosure () -> String,
                    category: LogCategory,
                    file: String = #file,
                    function: String = #function,
                    line: Int = #line,
                    metadata: [String: LogMetadataValue]? = nil) {
        let entry = LogEntry(level: level,
                             category: category,
                             subsystem: "com.logr.mock",
                             message: message(),
                             file: file,
                             function: function,
                             line: line,
                             metadata: metadata)

        mockLogs.insert(entry, at: 0)
        recentLogs.insert(entry, at: 0)

        // Keep only the most recent 100 entries for demo
        if mockLogs.count > 100 {
            mockLogs.removeLast()
        }
        if recentLogs.count > 100 {
            recentLogs.removeLast()
        }
    }

    public func clearLogs() async throws {
        mockLogs.removeAll()
        recentLogs.removeAll()
    }

    public func flush() async {}

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    public func scanForPrivacyIssues() async throws -> PrivacyAnalysisResult {
        PrivacyAnalysisResult(warnings: [
            PrivacyWarning(file: "LoginViewController.swift",
                           line: 42,
                           exposureType: "email",
                           exposedContent: "user@example.com",
                           explanation: "Email address is being logged in plain text, which could expose user identity.",
                           severity: .high,
                           recommendation: "Remove email logging or use hashed/redacted versions."),
            PrivacyWarning(file: "PaymentService.swift",
                           line: 158,
                           exposureType: "credit card",
                           exposedContent: "4532-1234-5678-1234",
                           explanation: "Full credit card number detected in logs - severe PCI compliance violation.",
                           severity: .critical,
                           recommendation: "Never log credit card numbers. Implement PCI-DSS compliant logging.")
        ],
        summary: "Found 2 potential privacy exposures: 1 critical, 1 high severity.",
        criticalCount: 1,
        highCount: 1)
    }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    public func summarizeIssues() async throws -> LogIssueSummary {
        LogIssueSummary(executiveSummary: "Analyzed 45 errors, 23 warnings, and 3 faults. Found 12 distinct issues: 2 critical, 4 high severity. Immediate action required on critical issues.",
                        issues: [
                            LogIssue(category: "error",
                                     title: "Network timeout in API requests",
                                     description: "Multiple API requests are timing out after 30 seconds, causing poor user experience.",
                                     file: "NetworkManager.swift",
                                     line: 156,
                                     occurrences: 23,
                                     severity: .high,
                                     suggestedFix: "Implement retry logic with exponential backoff and reduce timeout to 15s."),
                            LogIssue(category: "crash",
                                     title: "Force unwrap causing crashes",
                                     description: "Optional value is being force unwrapped without safety checks, leading to runtime crashes.",
                                     file: "DataParser.swift",
                                     line: 89,
                                     occurrences: 5,
                                     severity: .critical,
                                     suggestedFix: "Use optional binding (if let) or nil coalescing instead of force unwrap."),
                            LogIssue(category: "performance",
                                     title: "Main thread blocked by heavy computation",
                                     description: "Image processing is running on main thread causing UI freezes.",
                                     file: "ImageProcessor.swift",
                                     line: 234,
                                     occurrences: 12,
                                     severity: .medium,
                                     suggestedFix: "Move image processing to background queue using DispatchQueue.global().")
                        ],
                        totalErrors: 45,
                        totalWarnings: 23,
                        totalFaults: 3,
                        patterns: [
                            "3 error issues detected across multiple locations",
                            "High frequency of network-related errors during peak hours",
                            "Memory warnings correlate with image processing operations"
                        ],
                        priorityActions: [
                            "Force unwrap causing crashes (DataParser.swift:89)",
                            "Network timeout in API requests (NetworkManager.swift:156)",
                            "Memory leak in cache manager (CacheManager.swift:201)"
                        ])
    }

    // MARK: - Instant Generation

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
        recentLogs = entries
    }

    // MARK: - Streaming Generation

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
                recentLogs.append(contentsOf: entries)

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
            return "Unknow"
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
//// Generate 10,000 entries instantly (default config)
// let mockService = MockLogR(empty: false)
//
//// Generate 50,000 entries with custom config
// let heavyConfig = MockLogR.GenerationConfig(
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
//    config: MockLogR.GenerationConfig(totalEntries: 100_000),
//    mode: .stream(chunks: 100, delay: 0.1)
// )
