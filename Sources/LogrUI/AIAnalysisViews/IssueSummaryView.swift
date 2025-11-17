import Logr
import SwiftUI

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
public struct IssueSummaryView: View {
    let summary: LogIssueSummary

    public init(summary: LogIssueSummary) {
        self.summary = summary
    }

    public var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "chart.bar.doc.horizontal")
                            .foregroundStyle(.blue)
                            .font(.title2)

                        Text("Executive Summary")
                            .font(.headline)
                    }

                    Text(summary.executiveSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 16) {
                        statBadge(count: summary.totalErrors, label: "Errors", color: .red)
                        statBadge(count: summary.totalWarnings, label: "Warnings", color: .orange)
                        statBadge(count: summary.totalFaults, label: "Faults", color: .purple)
                    }
                }
                .padding(.vertical, 8)
            }

            if !summary.priorityActions.isEmpty {
                Section("Priority Actions") {
                    ForEach(Array(summary.priorityActions.enumerated()), id: \.offset) { index, action in
                        HStack {
                            Text("\(index + 1)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(priorityColor(for: index))
                                .clipShape(Circle())

                            Text(action)
                                .font(.subheadline)
                        }
                    }
                }
            }

            if !summary.patterns.isEmpty {
                Section("Patterns Detected") {
                    ForEach(Array(summary.patterns.enumerated()), id: \.offset) { _, pattern in
                        HStack {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .foregroundStyle(.blue)
                            Text(pattern)
                                .font(.subheadline)
                        }
                    }
                }
            }

            if !summary.issues.isEmpty {
                Section("All Issues (\(summary.issues.count))") {
                    ForEach(summary.issues) { issue in
                        IssueRow(issue: issue)
                    }
                }
            }
        }
        .navigationTitle("Issue Summary")
    }

    private func statBadge(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }

    private func priorityColor(for index: Int) -> Color {
        switch index {
        case 0: .red
        case 1: .orange
        case 2: .yellow
        default: .blue
        }
    }
}

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
struct IssueRow: View {
    let issue: LogIssue
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    categoryIcon
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.title)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        HStack(spacing: 8) {
                            Text(issue.category.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if issue.occurrences > 1 {
                                Text("•")
                                    .foregroundStyle(.secondary)
                                Text("\(issue.occurrences)× occurred")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer()

                    severityBadge

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()

                    IssueDetailRow(label: "Description", value: issue.description)

                    IssueDetailRow(label: "Location", value: "\(issue.file):\(issue.line)")
                        .monospaced()

                    IssueDetailRow(label: "Suggested Fix", value: issue.suggestedFix)
                        .foregroundStyle(.blue)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 8)
    }

    private var categoryIcon: some View {
        Group {
            switch issue.category.lowercased() {
            case "error":
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case "warning":
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            case "performance":
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .foregroundStyle(.yellow)
            case "crash":
                Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                    .foregroundStyle(.red)
            default:
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
    }

    private var severityBadge: some View {
        Text(issue.severity.capitalized)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(severityColor.opacity(0.2))
            .foregroundStyle(severityColor)
            .cornerRadius(6)
    }

    private var severityColor: Color {
        switch issue.severity.lowercased() {
        case "critical": .red
        case "high": .orange
        case "medium": .yellow
        default: .blue
        }
    }
}

struct IssueDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
        }
    }
}

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
#Preview {
    NavigationStack {
        IssueSummaryView(summary: LogIssueSummary(executiveSummary: "Analyzed 45 errors, 23 warnings, and 3 faults. Found 12 distinct issues: 2 critical, 4 high severity. Immediate action required on critical issues.",
                                                  issues: [
                                                      LogIssue(category: "error",
                                                               title: "Network timeout in API requests",
                                                               description: "Multiple API requests are timing out after 30 seconds, causing poor user experience.",
                                                               file: "NetworkManager.swift",
                                                               line: 156,
                                                               occurrences: 23,
                                                               severity: "high",
                                                               suggestedFix: "Implement retry logic with exponential backoff and reduce timeout to 15s."),
                                                      LogIssue(category: "crash",
                                                               title: "Force unwrap causing crashes",
                                                               description: "Optional value is being force unwrapped without safety checks, leading to runtime crashes.",
                                                               file: "DataParser.swift",
                                                               line: 89,
                                                               occurrences: 5,
                                                               severity: "critical",
                                                               suggestedFix: "Use optional binding (if let) or nil coalescing instead of force unwrap."),
                                                      LogIssue(category: "performance",
                                                               title: "Main thread blocked by heavy computation",
                                                               description: "Image processing is running on main thread causing UI freezes.",
                                                               file: "ImageProcessor.swift",
                                                               line: 234,
                                                               occurrences: 12,
                                                               severity: "medium",
                                                               suggestedFix: "Move image processing to background queue using DispatchQueue.global().")
                                                  ],
                                                  totalErrors: 45,
                                                  totalWarnings: 23,
                                                  totalFaults: 3,
                                                  patterns: [
                                                      "3 error issues detected across multiple locations",
                                                      "High frequency of network-related errors during peak hours",
                                                      "Memory warnings correlate with image processing operations"
                                                  ],
                                                  priorityActions: [
                                                      "Force unwrap causing crashes (DataParser.swift:89)",
                                                      "Network timeout in API requests (NetworkManager.swift:156)",
                                                      "Memory leak in cache manager (CacheManager.swift:201)"
                                                  ]))
    }
}
