//
//  LogStatisticsView.swift
//  Logr
//
//  Created by Claude on 28/11/2025.
//

import Charts
import Logr
import SwiftUI


/// A view displaying log statistics and metrics.
///
/// `LogStatisticsView` shows aggregated statistics about logs including
/// counts, distributions, and rates in a dashboard format.
///
/// ## Overview
///
/// The statistics view provides:
/// - Total log count with breakdown by level
/// - Error and warning rates
/// - Hourly distribution chart
/// - Top categories
///
/// ## Example
///
/// ```swift
/// LogStatisticsView(statistics: stats)
/// ```
public struct LogStatisticsView: View {
    @Environment(\.logService) private var logr

   private var statistics: LogStatistics {
        logr.logStatistics()
    }

    public init() {}

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                summarySection
                levelBreakdownSection
                hourlyDistributionSection
                topCategoriesSection
            }
            .padding()
        }
        .navigationTitle("Log Statistics")
    }

    @ViewBuilder
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatCard(
                    title: "Total Logs",
                    value: "\(statistics.totalCount)",
                    icon: "doc.text",
                    color: .blue
                )

                StatCard(
                    title: "Error Rate",
                    value: String(format: "%.1f%%", statistics.errorRate * 100),
                    icon: "exclamationmark.triangle",
                    color: statistics.errorRate > 0.1 ? .red : .orange
                )

                StatCard(
                    title: "Warning Rate",
                    value: String(format: "%.1f%%", statistics.warningRate * 100),
                    icon: "exclamationmark.circle",
                    color: .yellow
                )

                StatCard(
                    title: "Avg/Hour",
                    value: String(format: "%.1f", statistics.averageLogsPerHour),
                    icon: "clock",
                    color: .green
                )
            }
        }
        .padding()
        .background(.background.secondary)
        .cornerRadius(12)
    }

    @ViewBuilder
    private var levelBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Level Breakdown")
                .font(.headline)

            ForEach(LogLevel.allCases, id: \.self) { level in
                let count = statistics.countByLevel[level] ?? 0
                let percentage = statistics.totalCount > 0
                    ? Double(count) / Double(statistics.totalCount)
                    : 0

                HStack {
                    Circle()
                        .fill(colorForLevel(level))
                        .frame(width: 12, height: 12)

                    Text(level.displayName.capitalized)
                        .font(.subheadline)

                    Spacer()

                    Text("\(count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)

                    ProgressView(value: percentage)
                        .frame(width: 60)
                }
            }
        }
        .padding()
        .background(.background.secondary)
        .cornerRadius(12)
    }

    @ViewBuilder
    private var hourlyDistributionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hourly Distribution")
                .font(.headline)

            Chart(statistics.hourlyDataPoints) { point in
                BarMark(
                    x: .value("Hour", point.date, unit: .hour),
                    y: .value("Count", point.count)
                )
                .foregroundStyle(.blue.gradient)
            }
            .frame(height: 150)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                    AxisValueLabel(format: .dateTime.hour())
                }
            }

            if let peakHour = statistics.peakHour {
                HStack {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                    Text("Peak hour: \(peakHour):00")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.background.secondary)
        .cornerRadius(12)
    }

    @ViewBuilder
    private var topCategoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Categories")
                .font(.headline)

            let topCategories = statistics.topCategories(5)

            if topCategories.isEmpty {
                Text("No data available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(topCategories, id: \.category) { item in
                    HStack {
                        Text(item.category.displayName)
                            .font(.subheadline)

                        Spacer()

                        Text("\(item.count)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(.background.secondary)
        .cornerRadius(12)
    }

    private func colorForLevel(_ level: LogLevel) -> Color {
        switch level {
        case .debug:
            .gray
        case .info:
            .blue
        case .notice:
            .cyan
        case .warning:
            .orange
        case .error:
            .red
        case .fault:
            .purple
        }
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.title2.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.quaternary)
        .cornerRadius(8)
    }
}

// MARK: - Compact Statistics View

/// A compact inline statistics view for embedding in other views.
public struct CompactLogStatisticsView: View {
    let statistics: LogStatistics

    public init(statistics: LogStatistics) {
        self.statistics = statistics
    }

    public var body: some View {
        VStack(alignment: .leading) {
            Text("Logs summary")
                .fontWeight(.semibold)
            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Total:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(statistics.totalCount)")
                        .font(.headline.monospacedDigit())
                }
                
                Divider()
                    .frame(height: 30)
                HStack {
                    VStack {
                        Text("Errors")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(statistics.countByLevel[.error] ?? 0)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.red)
                    }
                    Divider()
                    VStack {
                        Text("Warnings")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(statistics.countByLevel[.warning] ?? 0)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.orange)
                    }
                }
                .padding()
                .background(.background.quaternary)
                .cornerRadius(12)
                
                Spacer()
                
                if statistics.errorRate > 0.05 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .padding()
        .background(.background.quaternary)
        .cornerRadius(12)
    }
}

// MARK: - Preview

#Preview("Log Statistics") {
     @Previewable @State var mock = MockLogR()
    NavigationStack {
        List {
            CompactLogStatisticsView(statistics: mock.logStatistics())
            .padding()
            LogStatisticsView()
        }
        .listStyle(.plain)
    }
    .environment(\.logService, mock)
}
