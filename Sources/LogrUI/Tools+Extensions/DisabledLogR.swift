//
//  DisabledLogR.swift
//  Logr
//
//  Created by martin on 02/06/2026.
//

import Collections
import DequeModule
import Foundation
import Logr

// MARK: - No-op Implementation

/// A no-op ``LogRService`` used as the default value for the `logService`
/// environment key when no real logger has been injected.
///
/// Every logging call is silently discarded, the log cache is always empty, and
/// AI analysis reports as unavailable. This lets `LogrUI` views render a safe,
/// empty state instead of forcing an optional environment value (and the side
/// effects of constructing a real ``LogR`` as a default).
///
/// Inject a real service with ``SwiftUICore/View/logRService(_:)`` (or
/// `.environment(\.logService, logger)`) to enable functionality.
@Observable
@MainActor
final class DisabledLogR: LogRService {
    var recentLogs: Deque<LogEntry> { Deque() }

    var canAnalyseLogs: Bool { false }

    var droppedLogCount: Int { 0 }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    var privacyAnalysisResult: PrivacyAnalysisResult? { nil }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    var logIssueSummary: LogIssueSummary? { nil }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    var analysisProgress: AnalysisProgress? { nil }

    init() {}

    func log(level: LogLevel,
             message: @autoclosure () -> String,
             category: LogCategory,
             file: String,
             function: String,
             line: Int,
             metadata: [String: LogMetadataValue]?) {}

    func clearLogs() async throws {}

    func flush() async {}

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    func scanForPrivacyIssues() async throws -> PrivacyAnalysisResult {
        throw AIAnalyzerError.missingAnalyzer
    }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    func summarizeIssues() async throws -> LogIssueSummary {
        throw AIAnalyzerError.missingAnalyzer
    }
}
