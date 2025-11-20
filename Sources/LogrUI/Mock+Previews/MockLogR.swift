//
//  MockLogR.swift
//  Logr
//
//  Created by Martin Lukacs on 16/11/2025.
//

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
    
    public init(
        totalEntries: Int = 5000,
        timeRange: TimeInterval = 86400, // 24 hours
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
        ]
    ) {
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
    public var canAnalyseLogs: Bool = true
    
    public private(set) var recentLogs: [LogEntry] = []
    public private(set) var isCleanupRunning = false

    private var mockLogs: [LogEntry] = []
    
    public init(
        empty: Bool = false,
        config: GenerationConfig = GenerationConfig(),
        mode: GenerationMode = .instant
    ) {
        if !empty {
            switch mode {
            case .instant:
                generateMockData(config: config)
            case .stream(let chunks, let delay):
                // For streaming, start with empty and stream in data
                Task {
                    await streamMockData(config: config, chunks: chunks, delay: delay)
                }
            }
        }
    }

    // MARK: - LogRService Implementation

    public func log(level: LogLevel,
                    message: String,
                    category: LogCategory,
                    file: String = #file,
                    function: String = #function,
                    line: Int = #line) {
        let entry = LogEntry(level: level,
                             category: category,
                             subsystem: "com.logr.mock",
                             message: message,
                             file: file,
                             function: function,
                             line: line)

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

    public func debug(_ message: String,
                      category: LogCategory,
                      file: String = #file,
                      function: String = #function,
                      line: Int = #line) async {
        log(level: .debug, message: message, category: category, file: file, function: function, line: line)
    }

    public func info(_ message: String,
                     category: LogCategory,
                     file: String = #file,
                     function: String = #function,
                     line: Int = #line) async {
        log(level: .info, message: message, category: category, file: file, function: function, line: line)
    }

    public func notice(_ message: String,
                       category: LogCategory,
                       file: String = #file,
                       function: String = #function,
                       line: Int = #line) async {
        log(level: .notice, message: message, category: category, file: file, function: function, line: line)
    }

    public func error(_ message: String,
                      category: LogCategory,
                      file: String = #file,
                      function: String = #function,
                      line: Int = #line) async {
        log(level: .error, message: message, category: category, file: file, function: function, line: line)
    }

    public func fault(_ message: String,
                      category: LogCategory,
                      file: String = #file,
                      function: String = #function,
                      line: Int = #line) async {
        log(level: .fault, message: message, category: category, file: file, function: function, line: line)
    }

    public func getLogs(levels: Set<LogLevel>? = nil,
                        categories: Set<LogCategory>? = nil,
                        subsystems: Set<String>? = nil,
                        from startDate: Date? = nil,
                        to endDate: Date? = nil,
                        limit: Int? = nil) async throws -> [LogEntry] {
        var filtered = mockLogs

        if let levels {
            filtered = filtered.filter { levels.contains($0.level) }
        }

        if let categories {
            filtered = filtered.filter { categories.contains($0.category) }
        }

        if let subsystems {
            filtered = filtered.filter { subsystems.contains($0.subsystem) }
        }

        if let startDate {
            filtered = filtered.filter { $0.timestamp >= startDate }
        }

        if let endDate {
            filtered = filtered.filter { $0.timestamp <= endDate }
        }

        filtered.sort { $0.timestamp > $1.timestamp }

        if let limit {
            filtered = Array(filtered.prefix(limit))
        }

        return filtered
    }

    public func clearLogs() async throws {
        mockLogs.removeAll()
        recentLogs.removeAll()
    }

    public func exportLogs(format: ExportFormat = .json) -> Data? {
        encode(for: format)
    }

    func encode(for exportFormat: ExportFormat) -> Data? {
        guard !mockLogs.isEmpty else { return nil }
        switch exportFormat {
        case .json:
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try? encoder.encode(recentLogs)

        case .csv:
            var csv = "Timestamp,Level,Category,Subsystem,Message,File,Function,Line\n"
            let formatter = ISO8601DateFormatter()

            for log in recentLogs {
                let timestamp = formatter.string(from: log.timestamp)
                let escapedMessage = log.message.replacingOccurrences(of: "\"", with: "\"\"")
                csv += "\"\(timestamp)\",\"\(log.level.rawValue)\",\"\(log.category)\",\"\(log.subsystem)\",\"\(escapedMessage)\",\"\(log.file)\",\"\(log.function)\",\(log.line)\n"
            }

            return csv.data(using: .utf8)

        case .txt:
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .long

            var text = ""
            for log in recentLogs {
                text += "[\(formatter.string(from: log.timestamp))] [\(log.level.displayName.uppercased())] [\(log.category)] \(log.message)\n"
            }

            return text.data(using: .utf8)
        }
    }
    
    // MARK: - Instant Generation
    
    private func generateMockData(config: GenerationConfig) {
        let now = Date()
        let totalProbability = config.levelDistribution.values.reduce(0, +)
        
        // Pre-allocate array for better performance
        var entries: [LogEntry] = []
        entries.reserveCapacity(config.totalEntries)
        
        for i in 0..<config.totalEntries {
            let timestamp = now.addingTimeInterval(
                -config.timeRange + (config.timeRange * Double(i) / Double(config.totalEntries))
            )
            
            let level = selectLevel(from: config.levelDistribution, totalProbability: totalProbability)
            let category = config.categories.randomElement() ?? .system
            let subsystem = config.subsystems.randomElement() ?? "com.logr.example"
            let message = generateMessage(for: level, category: category, index: i)
            
            entries.append(
                LogEntry(
                    timestamp: timestamp,
                    level: level,
                    category: category,
                    subsystem: subsystem,
                    message: message
                )
            )
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
                let timestamp = now.addingTimeInterval(
                    -config.timeRange + (config.timeRange * Double(i) / Double(config.totalEntries))
                )
                
                let level = selectLevel(from: config.levelDistribution, totalProbability: totalProbability)
                let category = config.categories.randomElement() ?? .system
                let subsystem = config.subsystems.randomElement() ?? "com.logr.example"
                let message = generateMessage(for: level, category: category, index: i)
                
                entries.append(
                    LogEntry(
                        timestamp: timestamp,
                        level: level,
                        category: category,
                        subsystem: subsystem,
                        message: message
                    )
                )
            }
            
            // Update on main actor in batches
            await MainActor.run {
                mockLogs.append(contentsOf: entries)
                recentLogs.append(contentsOf: entries)
            }
            
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
//let mockService = MockLogR(empty: false)
//
//// Generate 50,000 entries with custom config
//let heavyConfig = MockLogR.GenerationConfig(
//    totalEntries: 50_000,
//    timeRange: 604800, // 7 days
//    levelDistribution: [
//        .debug: 0.5,
//        .info: 0.25,
//        .notice: 0.15,
//        .error: 0.08,
//        .fault: 0.02
//    ]
//)
//let heavyMockService = MockLogR(config: heavyConfig)
//
//// Stream 100,000 entries in chunks for simulated real-time updates
//let streamingService = MockLogR(
//    config: MockLogR.GenerationConfig(totalEntries: 100_000),
//    mode: .stream(chunks: 100, delay: 0.1)
//)
