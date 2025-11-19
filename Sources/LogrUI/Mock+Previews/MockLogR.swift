//
//  MockLogR.swift
//  Logr
//
//  Created by Martin Lukacs on 16/11/2025.
//

import Foundation
import Logr

// MARK: - Mock Implementation

@Observable
@MainActor
public final class MockLogR: LogRService, Sendable {
    public private(set) var recentLogs: [LogEntry] = []
    public private(set) var isCleanupRunning = false

    private var mockLogs: [LogEntry] = []

    public init() {
        generateMockData()
    }

    private func generateMockData() {
        let mockEntries: [LogEntry] = [
            LogEntry(timestamp: Date().addingTimeInterval(-300),
                     level: .info,
                     category: .system,
                     subsystem: "com.logr.example",
                     message: "Application launched successfully"),
            LogEntry(timestamp: Date().addingTimeInterval(-240),
                     level: .debug,
                     category: .network,
                     subsystem: "com.logr.example",
                     message: "Network request initiated to api.example.com"),
            LogEntry(timestamp: Date().addingTimeInterval(-180),
                     level: .notice,
                     category: .ui,
                     subsystem: "com.logr.example",
                     message: "Main view controller loaded"),
            LogEntry(timestamp: Date().addingTimeInterval(-120),
                     level: .error,
                     category: .authentication,
                     subsystem: "com.logr.example",
                     message: "Failed to authenticate user - invalid credentials"),
            LogEntry(timestamp: Date().addingTimeInterval(-60),
                     level: .fault,
                     category: .database,
                     subsystem: "com.logr.example",
                     message: "Critical database connection error - attempting recovery"),
            LogEntry(timestamp: Date().addingTimeInterval(-30),
                     level: .info,
                     category: .custom("business-logic"),
                     subsystem: "com.logr.example",
                     message: "Order processing completed for order #12345"),
            LogEntry(timestamp: Date(),
                     level: .debug,
                     category: .performance,
                     subsystem: "com.logr.example",
                     message: "Memory usage: 45MB, CPU: 12%")
        ]

        mockLogs = mockEntries
        recentLogs = mockEntries
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

    public func exportLogs(format: ExportFormat = .json) async throws -> Data? {
        try encode(for: format)
    }
    
    func encode(for exportFormat: ExportFormat) throws -> Data? {
        guard !mockLogs.isEmpty else { return nil }
        switch exportFormat {
        case .json:
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(recentLogs)

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
}
