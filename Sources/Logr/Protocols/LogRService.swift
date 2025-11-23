//
//  LogRService.swift
//  Logr
//
//  Created by Martin Lukacs on 16/11/2025.
//

import Foundation

@MainActor
public protocol LogRService: Observable, Sendable {
    var recentLogs: [LogEntry] { get }
    var canAnalyseLogs: Bool { get }
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    var privacyAnalysisResult: PrivacyAnalysisResult? { get }
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    var logIssueSummary: LogIssueSummary? { get }

    // Core logging methods
    func log(level: LogLevel,
             message: String,
             category: LogCategory,
             file: String,
             function: String,
             line: Int)

    func exportLogs(format: ExportFormat) -> Data?
    func clearLogs() async throws

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    @discardableResult func scanForPrivacyIssues() async throws -> PrivacyAnalysisResult
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    @discardableResult func summarizeIssues() async throws -> LogIssueSummary
}

// MARK: - Helper functions

public extension LogRService {
    func debug(_ message: String,
               category: LogCategory = .debug,
               file: String = #file,
               function: String = #function,
               line: Int = #line) {
        log(level: .debug, message: message, category: category, file: file, function: function, line: line)
    }

    func info(_ message: String,
              category: LogCategory = .system,
              file: String = #file,
              function: String = #function,
              line: Int = #line) {
        log(level: .info, message: message, category: category, file: file, function: function, line: line)
    }

    func notice(_ message: String,
                category: LogCategory = .system,
                file: String = #file,
                function: String = #function,
                line: Int = #line) {
        log(level: .notice, message: message, category: category, file: file, function: function, line: line)
    }

    func error(_ message: String,
               category: LogCategory = .system,
               file: String = #file,
               function: String = #function,
               line: Int = #line) {
        log(level: .error, message: message, category: category, file: file, function: function, line: line)
    }

    func fault(_ message: String,
               category: LogCategory = .system,
               file: String = #file,
               function: String = #function,
               line: Int = #line) {
        log(level: .fault, message: message, category: category, file: file, function: function, line: line)
    }
}
