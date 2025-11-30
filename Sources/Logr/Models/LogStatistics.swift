//
//  LogStatistics.swift
//  Logr
//
//  Created by Claude on 28/11/2025.
//

import Collections
import Foundation

/// Statistics and metrics computed from log entries.
///
/// `LogStatistics` provides aggregated metrics about logs, including counts
/// by level and category, time-based distributions, and error rate calculations.
///
/// ## Overview
///
/// Use log statistics to display dashboards, detect anomalies, and analyze
/// logging patterns over time.
///
/// ## Example
///
/// ```swift
/// let stats = LogStatistics.compute(from: logger.recentLogs)
/// print("Error rate: \(stats.errorRate * 100)%")
/// print("Busiest hour: \(stats.peakHour)")
/// ```
///
/// ## Topics
///
/// ### Computing Statistics
/// - ``compute(from:)``
///
/// ### Count Metrics
/// - ``totalCount``
/// - ``countByLevel``
/// - ``countByCategory``
///
/// ### Time-Based Metrics
/// - ``hourlyDistribution``
/// - ``dailyDistribution``
/// - ``peakHour``
///
/// ### Rate Metrics
/// - ``errorRate``
/// - ``warningRate``
public struct LogStatistics: Sendable, Equatable {
    public let totalCount: Int
    public let countByLevel: [LogLevel: Int]
    public let countByCategory: [LogCategory: Int]
    public let hourlyDistribution: [Int: Int]
    public let dailyDistribution: [Date: Int]
    public let peakHour: Int?
    public let dateRange: ClosedRange<Date>?

    public init(totalCount: Int,
                countByLevel: [LogLevel: Int],
                countByCategory: [LogCategory: Int],
                hourlyDistribution: [Int: Int],
                dailyDistribution: [Date: Int],
                peakHour: Int?,
                dateRange: ClosedRange<Date>?) {
        self.totalCount = totalCount
        self.countByLevel = countByLevel
        self.countByCategory = countByCategory
        self.hourlyDistribution = hourlyDistribution
        self.dailyDistribution = dailyDistribution
        self.peakHour = peakHour
        self.dateRange = dateRange
    }

    // MARK: - Computed Metrics

    public var errorRate: Double {
        calculateRate(for: [.error, .fault])
    }

    public var warningRate: Double {
        calculateRate(for: [.warning])
    }

    private func calculateRate(for levels: [LogLevel]) -> Double {
        guard totalCount > 0 else { return 0 }
        let levelCount = levels.reduce(0) { $0 + (countByLevel[$1] ?? 0) }
        return Double(levelCount) / Double(totalCount)
    }

    public var averageLogsPerHour: Double {
        guard let range = dateRange, range.upperBound > range.lowerBound else { return 0 }
        let hours = range.upperBound.timeIntervalSince(range.lowerBound) / 3_600
        return Double(totalCount) / hours
    }

    public static let empty = LogStatistics(totalCount: 0,
                                            countByLevel: [:],
                                            countByCategory: [:],
                                            hourlyDistribution: [:],
                                            dailyDistribution: [:],
                                            peakHour: nil,
                                            dateRange: nil)
}

// MARK: - Time Series Data Point

public struct LogTimeSeriesPoint: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let date: Date
    public let count: Int
    public let level: LogLevel?

    public init(id: UUID = UUID(),
                date: Date,
                count: Int,
                level: LogLevel? = nil) {
        self.id = id
        self.date = date
        self.count = count
        self.level = level
    }
}

// MARK: - Statistics Extensions

public extension LogStatistics {
    var hourlyDataPoints: [LogTimeSeriesPoint] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())

        return (0..<24).compactMap { hour in
            guard let date = calendar
                .date(byAdding: .hour, value: hour, to: todayStart) else {
                return nil
            }
            return LogTimeSeriesPoint(date: date, count: hourlyDistribution[hour] ?? 0)
        }
    }

    var dailyDataPoints: [LogTimeSeriesPoint] {
        dailyDistribution
            .map { LogTimeSeriesPoint(date: $0.key, count: $0.value) }
            .sorted { $0.date < $1.date }
    }

    func topCategories(_ count: Int = 5) -> [(category: LogCategory, count: Int)] {
        countByCategory
            .sorted { $0.value > $1.value }
            .prefix(count)
            .map { (category: $0.key, count: $0.value) }
    }

    var levelPercentages: [LogLevel: Double] {
        guard totalCount > 0 else { return [:] }
        return countByLevel.mapValues { Double($0) / Double(totalCount) * 100 }
    }
}
