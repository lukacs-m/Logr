//
//  LogFilterPreferences.swift
//  Logr
//
//  Created by Claude on 28/11/2025.
//

import Foundation
import Logr

/// Manages persistence of log viewer filter preferences.
///
/// `LogFilterPreferences` saves and restores filter selections using UserDefaults,
/// allowing the log viewer to remember user preferences between sessions.
///
/// ## Usage
///
/// ```swift
/// let prefs = LogFilterPreferences()
///
/// // Save current filters
/// prefs.saveSelectedLevels([.error, .warning])
/// prefs.saveSelectedCategories([.network])
///
/// // Load saved filters
/// let levels = prefs.loadSelectedLevels()
/// let categories = prefs.loadSelectedCategories()
/// ```
///

//@State private var selectedLevels: Set<LogLevel> = Set(LogLevel.allCases)
//@State private var selectedCategories: Set<LogCategory> = []
//@State private var allExpanded = false
//
//@State private var timeGrouping: LogTimeGrouping = .none
//@State private var showStatisticsPanel = false
//

@MainActor
@Observable
public final class LogFilterPreferences {
    private(set) var selectedLevels: Set<LogLevel> = []
    private(set) var selectedCategories: Set<LogCategory> = []
    private(set) var timeGrouping: LogTimeGrouping = .none
    var allExpanded = false
    var showStatisticsPanel = false {
        didSet {
            defaults.set(showStatisticsPanel, forKey: Keys.showStatisticsPanel)
        }
    }

    private let defaults: UserDefaults
    private let suiteName: String?

    private enum Keys {
        static let selectedLevels = "logr.filter.selectedLevels"
        static let selectedCategories = "logr.filter.selectedCategories"
        static let timeGrouping = "logr.filter.timeGrouping"
        static let showStatisticsPanel = "logr.filter.showStatisticsPanel"
    }

    /// Creates a new preferences manager.
    ///
    /// - Parameter suiteName: Optional UserDefaults suite name for app groups.
    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
        if let suiteName {
            defaults = UserDefaults(suiteName: suiteName) ?? .standard
        } else {
            defaults = .standard
        }
        setUp()
    }

    // MARK: - Selected Levels

    /// Saves the selected log levels.
    public func saveSelectedLevels(_ levels: Set<LogLevel>) {
        let rawValues = levels.map(\.rawValue)
        defaults.set(rawValues, forKey: Keys.selectedLevels)
        selectedLevels = levels
    }

    /// Loads previously saved log levels, or returns all levels if none saved.
    public func loadSelectedLevels() -> Set<LogLevel> {
        guard let rawValues = defaults.stringArray(forKey: Keys.selectedLevels) else {
            return Set(LogLevel.allCases)
        }
        let levels = rawValues.compactMap { LogLevel(rawValue: $0) }
        return levels.isEmpty ? Set(LogLevel.allCases) : Set(levels)
    }

    // MARK: - Selected Categories

    /// Saves the selected categories.
    public func saveSelectedCategories(_ categories: Set<LogCategory>) {
        let rawValues = categories.map(\.rawValue)
        defaults.set(rawValues, forKey: Keys.selectedCategories)
        selectedCategories = categories
    }

    /// Loads previously saved categories.
    public func loadSelectedCategories() -> Set<LogCategory> {
        guard let rawValues = defaults.stringArray(forKey: Keys.selectedCategories) else {
            return []
        }
        return Set(rawValues.compactMap { LogCategory(rawValue: $0) })
    }

    // MARK: - Time Grouping

    /// Saves the selected time grouping mode.
    public func saveTimeGrouping(_ grouping: LogTimeGrouping) {
        defaults.set(grouping.rawValue, forKey: Keys.timeGrouping)
        timeGrouping = grouping
    }

    /// Loads the previously saved time grouping mode.
    public func loadTimeGrouping() -> LogTimeGrouping {
        guard let rawValue = defaults.string(forKey: Keys.timeGrouping),
              let grouping = LogTimeGrouping(rawValue: rawValue) else {
            return .none
        }
        return grouping
    }

    // MARK: - Statistics Panel

    /// Saves whether the statistics panel is shown.
    public func saveShowStatisticsPanel(_ show: Bool) {
        defaults.set(show, forKey: Keys.showStatisticsPanel)
    }

    /// Loads whether the statistics panel should be shown.
    public func loadShowStatisticsPanel() -> Bool {
        defaults.bool(forKey: Keys.showStatisticsPanel)
    }

    // MARK: - Clear All

    /// Clears all saved preferences.
    public func clearAll() {
        defaults.removeObject(forKey: Keys.selectedLevels)
        defaults.removeObject(forKey: Keys.selectedCategories)
        defaults.removeObject(forKey: Keys.timeGrouping)
        defaults.removeObject(forKey: Keys.showStatisticsPanel)
    }
}

private extension LogFilterPreferences {
    func setUp() {
        selectedLevels = loadSelectedLevels()
        selectedCategories = loadSelectedCategories()
        timeGrouping = loadTimeGrouping()
        if showStatisticsPanel != loadShowStatisticsPanel() {
            showStatisticsPanel = loadShowStatisticsPanel()
        }
    }
}



// MARK: - Time Grouping

/// Time-based grouping options for log entries.
public enum LogTimeGrouping: String, CaseIterable, Identifiable, Sendable {
    /// No grouping - show all logs in a flat list.
    case none
    /// Group by relative time periods (today, yesterday, this week, etc.).
    case relative
    /// Group by date.
    case daily
    /// Group by hour.
    case hourly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: "None"
        case .relative: "Relative (Today, Yesterday...)"
        case .daily: "By Date"
        case .hourly: "By Hour"
        }
    }
}

// MARK: - Log Time Group

/// Represents a group of logs for time-based display.
public struct LogTimeGroup: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let logs: [LogEntry]

    public init(id: String, title: String, logs: [LogEntry]) {
        self.id = id
        self.title = title
        self.logs = logs
    }
}

// MARK: - Grouping Logic

extension [LogEntry]/*Array where Element == LogEntry*/ {
    /// Groups log entries by the specified time grouping.
    func grouped(by grouping: LogTimeGrouping) -> [LogTimeGroup] {
        switch grouping {
        case .none:
            return [LogTimeGroup(id: "all", title: "All Logs", logs: self)]

        case .relative:
            return groupedByRelativeTime()

        case .daily:
            return groupedByDay()

        case .hourly:
            return groupedByHour()
        }
    }

    private func groupedByRelativeTime() -> [LogTimeGroup] {
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        let thisWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
        let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart)!
        let thisMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!

        var groups: [String: [LogEntry]] = [:]
        let order = ["today", "yesterday", "thisWeek", "lastWeek", "thisMonth", "older"]

        for entry in self {
            let key: String
            if entry.timestamp >= todayStart {
                key = "today"
            } else if entry.timestamp >= yesterdayStart {
                key = "yesterday"
            } else if entry.timestamp >= thisWeekStart {
                key = "thisWeek"
            } else if entry.timestamp >= lastWeekStart {
                key = "lastWeek"
            } else if entry.timestamp >= thisMonthStart {
                key = "thisMonth"
            } else {
                key = "older"
            }
            groups[key, default: []].append(entry)
        }

        let titles: [String: String] = [
            "today": "Today",
            "yesterday": "Yesterday",
            "thisWeek": "This Week",
            "lastWeek": "Last Week",
            "thisMonth": "This Month",
            "older": "Older"
        ]

        return order.compactMap { key in
            guard let logs = groups[key], !logs.isEmpty else { return nil }
            return LogTimeGroup(id: key, title: titles[key] ?? key, logs: logs)
        }
    }

    private func groupedByDay() -> [LogTimeGroup] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        var groups: [Date: [LogEntry]] = [:]

        for entry in self {
            let dayStart = calendar.startOfDay(for: entry.timestamp)
            groups[dayStart, default: []].append(entry)
        }

        return groups
            .sorted { $0.key > $1.key }
            .map { LogTimeGroup(id: $0.key.ISO8601Format(), title: formatter.string(from: $0.key), logs: $0.value) }
    }

    private func groupedByHour() -> [LogTimeGroup] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:00 a"

        var groups: [Date: [LogEntry]] = [:]

        for entry in self {
            let components = calendar.dateComponents([.year, .month, .day, .hour], from: entry.timestamp)
            if let hourStart = calendar.date(from: components) {
                groups[hourStart, default: []].append(entry)
            }
        }

        return groups
            .sorted { $0.key > $1.key }
            .map { LogTimeGroup(id: $0.key.ISO8601Format(), title: formatter.string(from: $0.key), logs: $0.value) }
    }
}
