import Logr
import SwiftUI

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
public struct IssueSummaryView: View {
    @Environment(\.logService) var logr
    @State private var loading = false
    @State private var showError: Error?

    public init() {}

    public var body: some View {
        mainContent
            .navigationTitle("Issue Summary")
            .toolbar {
                toolbarContent
            }
            .overlay {
                overlayContent
            }
            .task {
                await loadData()
            }
            .errorAlert(error: $showError)
    }

    private func priorityColor(for index: Int) -> Color {
        switch index {
        case 0: .red
        case 1: .orange
        case 2: .yellow
        default: .blue
        }
    }

    private func loadData(reload: Bool = false) async {
        guard (reload || logr.logIssueSummary == nil) else {
            return
        }
        defer { loading = false }

        do {
            loading = true
            try await logr.summarizeIssues()
        } catch {
            showError = error
        }
    }
}

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
private extension IssueSummaryView {
    var mainContent: some View {
        List {
            summaryView
            actionView
            patternView
            issuesView
        }
    }

    @ViewBuilder
    var summaryView: some View {
        if let summary = logr.logIssueSummary {
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
                        StatBadgeView(count: summary.totalErrors, label: "Errors", color: .red)
                        StatBadgeView(count: summary.totalWarnings, label: "Warnings", color: .orange)
                        StatBadgeView(count: summary.totalFaults, label: "Faults", color: .purple)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    var actionView: some View {
        if let summary = logr.logIssueSummary, !summary.priorityActions.isEmpty {
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
    }

    @ViewBuilder
    var patternView: some View {
        if let summary = logr.logIssueSummary, !summary.patterns.isEmpty {
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
    }

    @ViewBuilder
    var issuesView: some View {
        if let summary = logr.logIssueSummary, !summary.issues.isEmpty {
            Section("All Issues (\(summary.issues.count))") {
                ForEach(summary.issues) { issue in
                    IssueRow(issue: issue)
                }
            }
        }
    }
}

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
private extension IssueSummaryView {
    var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if logr.logIssueSummary != nil {
                Button("ReScan") {
                    Task {
                        await loadData(reload: true)
                    }
                }
            }
        }
    }
}

// MARK: - Overlay

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
private extension IssueSummaryView {
    @ViewBuilder
    var overlayContent: some View {
        if loading {
            AnalyzeProcessingView()
        } else if let summary = logr.logIssueSummary, summary.isEmpty {
            ContentUnavailableView {
                Image(systemName: "text.page.badge.magnifyingglass")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 210, height: 120)
                    .padding(.bottom, 16)
            } description: {
                VStack(spacing: 8) {
                    Text("No issues detected in your logs yet")
                        .font(.title2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .top)
                        .opacity(0.9)
                    Text("Nothing to report here. Try adding some logs if an issue is reported")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .top)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                }
                .padding(.horizontal, 16)
            } actions: {}
        }
    }
}

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
struct IssueRow: View {
    let issue: LogIssue
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                IssueDetailRow(label: "Description", value: issue.description)

                IssueDetailRow(label: "Location", value: "\(issue.file):\(issue.line)")
                    .monospaced()

                IssueDetailRow(label: "Suggested Fix", value: issue.suggestedFix)
                    .foregroundStyle(.blue)
            }
        } label: {
            mainContent
        }
    }

    var mainContent: some View {
        VStack(alignment: .leading, spacing: 4) {
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
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }
        }
    }

    private var categoryIcon: some View {
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

// MARK: - SubViews

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

struct StatBadgeView: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
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
}

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
#Preview {
    @Previewable @State var mock = MockLogR()
    NavigationStack {
        IssueSummaryView()
    }
    .environment(\.logService, mock)
}
