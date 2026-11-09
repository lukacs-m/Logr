//
//  AnalysisProgress.swift
//  Logr
//
//  Created by Claude on 27/11/2025.
//

import Foundation

/// How far ``LogRService/summarizeIssues()`` has got through the issue groups of a ``LogIssueDigest``.
public struct AnalysisProgress: Sendable, Equatable {
    /// The number of issue groups being summarized.
    public let totalGroups: Int

    /// The number of issue groups summarized so far.
    public let analyzedGroups: Int

    /// The completion fraction (0.0 to 1.0).
    public var progress: Double {
        guard totalGroups > 0 else { return 0 }
        return Double(analyzedGroups) / Double(totalGroups)
    }

    /// The completion percentage as an integer (0 to 100).
    public var percentComplete: Int {
        Int(progress * 100)
    }

    /// Whether every group has been summarized.
    public var isComplete: Bool {
        analyzedGroups >= totalGroups
    }

    /// - Parameters:
    ///   - totalGroups: The number of issue groups to summarize.
    ///   - analyzedGroups: The number summarized so far, capped at `totalGroups`.
    public init(totalGroups: Int, analyzedGroups: Int) {
        self.totalGroups = totalGroups
        self.analyzedGroups = min(analyzedGroups, totalGroups)
    }

    /// No analysis.
    public static var empty: AnalysisProgress {
        AnalysisProgress(totalGroups: 0, analyzedGroups: 0)
    }

    /// The start of a summary over `totalGroups` issue groups.
    public static func starting(totalGroups: Int) -> AnalysisProgress {
        AnalysisProgress(totalGroups: totalGroups, analyzedGroups: 0)
    }
}
