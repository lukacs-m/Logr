//
//  AnalysisProgress.swift
//  Logr
//
//  Created by Claude on 27/11/2025.
//

import Foundation

/// Represents the progress of an AI analysis operation.
///
/// This struct tracks the current state of log analysis, including
/// how many logs have been processed and the overall completion percentage.
@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
public struct AnalysisProgress: Sendable, Equatable {
    /// The total number of logs being analyzed.
    public let totalLogs: Int

    /// The number of logs that have been analyzed so far.
    public let analyzedLogs: Int

    /// The completion percentage (0.0 to 1.0).
    public var progress: Double {
        guard totalLogs > 0 else { return 0 }
        return Double(analyzedLogs) / Double(totalLogs)
    }

    /// The completion percentage as an integer (0 to 100).
    public var percentComplete: Int {
        Int(progress * 100)
    }

    /// Whether the analysis is complete.
    public var isComplete: Bool {
        analyzedLogs >= totalLogs
    }

    /// Creates a new analysis progress instance.
    /// - Parameters:
    ///   - totalLogs: The total number of logs to analyze.
    ///   - analyzedLogs: The number of logs analyzed so far.
    public init(totalLogs: Int, analyzedLogs: Int) {
        self.totalLogs = totalLogs
        self.analyzedLogs = min(analyzedLogs, totalLogs)
    }

    /// An empty progress instance representing no analysis.
    public static var empty: AnalysisProgress {
        AnalysisProgress(totalLogs: 0, analyzedLogs: 0)
    }

    /// Creates a progress instance for the start of analysis.
    /// - Parameter totalLogs: The total number of logs to analyze.
    /// - Returns: A progress instance with zero analyzed logs.
    public static func starting(totalLogs: Int) -> AnalysisProgress {
        AnalysisProgress(totalLogs: totalLogs, analyzedLogs: 0)
    }
}
