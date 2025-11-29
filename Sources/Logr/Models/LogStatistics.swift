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
//public struct LogStatistics: Sendable, Equatable {
//    /// Total number of log entries.
//    public let totalCount: Int
//
//    /// Count of entries per log level.
//    public let countByLevel: [LogLevel: Int]
//
//    /// Count of entries per category.
//    public let countByCategory: [LogCategory: Int]
//
//    /// Distribution of logs by hour of day (0-23).
//    public let hourlyDistribution: [Int: Int]
//
//    /// Distribution of logs by day (Date without time component).
//    public let dailyDistribution: [Date: Int]
//
//    /// The hour with the most log entries (0-23).
//    public let peakHour: Int?
//
//    /// The date range covered by the logs.
//    public let dateRange: ClosedRange<Date>?
//
//    /// Creates a new LogStatistics instance.
//    public init(
//        totalCount: Int,
//        countByLevel: [LogLevel: Int],
//        countByCategory: [LogCategory: Int],
//        hourlyDistribution: [Int: Int],
//        dailyDistribution: [Date: Int],
//        peakHour: Int?,
//        dateRange: ClosedRange<Date>?
//    ) {
//        self.totalCount = totalCount
//        self.countByLevel = countByLevel
//        self.countByCategory = countByCategory
//        self.hourlyDistribution = hourlyDistribution
//        self.dailyDistribution = dailyDistribution
//        self.peakHour = peakHour
//        self.dateRange = dateRange
//    }
//
//    /// Ratio of error and fault logs to total logs (0.0 to 1.0).
//    public var errorRate: Double {
//        guard totalCount > 0 else { return 0 }
//        let errorCount = (countByLevel[.error] ?? 0) + (countByLevel[.fault] ?? 0)
//        return Double(errorCount) / Double(totalCount)
//    }
//
//    /// Ratio of warning logs to total logs (0.0 to 1.0).
//    public var warningRate: Double {
//        guard totalCount > 0 else { return 0 }
//        return Double(countByLevel[.warning] ?? 0) / Double(totalCount)
//    }
//
//    /// Average logs per hour based on the time range covered.
//    public var averageLogsPerHour: Double {
//        guard let range = dateRange else { return 0 }
//        let hours = range.upperBound.timeIntervalSince(range.lowerBound) / 3600
//        guard hours > 0 else { return Double(totalCount) }
//        return Double(totalCount) / hours
//    }
//
//    /// Computes statistics from a collection of log entries.
//    ///
//    /// - Parameter logs: The log entries to analyze.
//    /// - Returns: Computed statistics.
//    ///
//    /// ## Example
//    /// ```swift
//    /// let stats = LogStatistics.compute(from: logger.recentLogs)
//    /// ```
//    public static func compute(from logs: some Collection<LogEntry>) -> LogStatistics {
//        guard !logs.isEmpty else {
//            return LogStatistics(
//                totalCount: 0,
//                countByLevel: [:],
//                countByCategory: [:],
//                hourlyDistribution: [:],
//                dailyDistribution: [:],
//                peakHour: nil,
//                dateRange: nil
//            )
//        }
//
//        var countByLevel: [LogLevel: Int] = [:]
//        var countByCategory: [LogCategory: Int] = [:]
//        var hourlyDistribution: [Int: Int] = [:]
//        var dailyDistribution: [Date: Int] = [:]
//
//        let calendar = Calendar.current
//
//        var minDate: Date?
//        var maxDate: Date?
//
//        for log in logs {
//            // Count by level
//            countByLevel[log.level, default: 0] += 1
//
//            // Count by category
//            countByCategory[log.category, default: 0] += 1
//
//            // Hourly distribution
//            let hour = calendar.component(.hour, from: log.timestamp)
//            hourlyDistribution[hour, default: 0] += 1
//
//            // Daily distribution
//            let dayStart = calendar.startOfDay(for: log.timestamp)
//            dailyDistribution[dayStart, default: 0] += 1
//
//            // Track date range
//            if minDate == nil || log.timestamp < minDate! {
//                minDate = log.timestamp
//            }
//            if maxDate == nil || log.timestamp > maxDate! {
//                maxDate = log.timestamp
//            }
//        }
//
//        let peakHour = hourlyDistribution.max(by: { $0.value < $1.value })?.key
//
//        let dateRange: ClosedRange<Date>? = if let min = minDate, let max = maxDate {
//            min...max
//        } else {
//            nil
//        }
//
//        return LogStatistics(
//            totalCount: logs.count,
//            countByLevel: countByLevel,
//            countByCategory: countByCategory,
//            hourlyDistribution: hourlyDistribution,
//            dailyDistribution: dailyDistribution,
//            peakHour: peakHour,
//            dateRange: dateRange
//        )
//    }
//}
//
//// MARK: - Time Series Data Point
//
///// A data point for time-series chart display.
//public struct LogTimeSeriesPoint: Identifiable, Sendable, Equatable {
//    public let id: String
//    public let date: Date
//    public let count: Int
//    public let level: LogLevel?
//
//    public init(id: String = UUID().uuidString,
//                date: Date,
//                count: Int,
//                level: LogLevel? = nil) {
//        self.id = id
//        self.date = date
//        self.count = count
//        self.level = level
//    }
//}
//
//// MARK: - Statistics Extensions
//
//public extension LogStatistics {
//    /// Returns hourly data points for chart display.
//    var hourlyDataPoints: [LogTimeSeriesPoint] {
//        let calendar = Calendar.current
//        let now = Date()
//        let todayStart = calendar.startOfDay(for: now)
//
//        return (0..<24).map { hour in
//            let date = calendar.date(byAdding: .hour, value: hour, to: todayStart)!
//            let count = hourlyDistribution[hour] ?? 0
//            return LogTimeSeriesPoint(date: date, count: count)
//        }
//    }
//
//    /// Returns daily data points for chart display.
//    var dailyDataPoints: [LogTimeSeriesPoint] {
//        dailyDistribution
//            .map { LogTimeSeriesPoint(date: $0.key, count: $0.value) }
//            .sorted { $0.date < $1.date }
//    }
//
//    /// Returns the top N categories by log count.
//    func topCategories(_ count: Int = 5) -> [(category: LogCategory, count: Int)] {
//        countByCategory
//            .sorted { $0.value > $1.value }
//            .prefix(count)
//            .map { (category: $0.key, count: $0.value) }
//    }
//
//    /// Returns level distribution as percentages.
//    var levelPercentages: [LogLevel: Double] {
//        guard totalCount > 0 else { return [:] }
//        return countByLevel.mapValues { Double($0) / Double(totalCount) * 100 }
//    }
//}

public struct LogStatistics: Sendable, Equatable {
    public let totalCount: Int
    public let countByLevel: [LogLevel: Int]
    public let countByCategory: [LogCategory: Int]
    public let hourlyDistribution: [Int: Int]
    public let dailyDistribution: [Date: Int]
    public let peakHour: Int?
    public let dateRange: ClosedRange<Date>?
    
    public init(totalCount: Int,
         countByLevel: [LogLevel : Int],
         countByCategory: [LogCategory : Int],
         hourlyDistribution: [Int : Int],
         dailyDistribution: [Date : Int],
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
        let hours = range.upperBound.timeIntervalSince(range.lowerBound) / 3600
        return Double(totalCount) / hours
    }

    public static let empty = LogStatistics(
        totalCount: 0,
        countByLevel: [:],
        countByCategory: [:],
        hourlyDistribution: [:],
        dailyDistribution: [:],
        peakHour: nil,
        dateRange: nil
    )
}

// MARK: - Time Series Data Point

public struct LogTimeSeriesPoint: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let date: Date
    public let count: Int
    public let level: LogLevel?

    public init(
        id: UUID = UUID(),
        date: Date,
        count: Int,
        level: LogLevel? = nil
    ) {
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
