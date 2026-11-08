import Logr
import SwiftUI

/// Lists the warning, error and fault entries grouped by call site (`LogRService.issueDigest()`), on every
/// platform. While `LogRService.canAnalyseLogs` is true, a button explains the groups with
/// `LogRService.summarizeIssues()`.
public struct IssueSummaryView: View {
    @Environment(\.logService) var logr
    @State private var digest: LogIssueDigest?
    @State private var showError: Error?
    /// A summary to run in `.task(id:)`, which cancels it when the view goes away: it can take minutes.
    @State private var request: Request?
    @State private var requestCount = 0
    /// One per start of the task: a cancelled run can end after its replacement started, same request or not.
    @State private var running: Run?
    @State private var starts = 0

    private struct Run: Equatable {
        let start: Int
        /// The model is at work, not only the digest reloading.
        var explaining: Bool
    }

    private struct Request: Equatable {
        let id: Int
        /// Reload the digest first, then summarize only when a summary is shown.
        let reload: Bool
    }

    public init() {}

    public var body: some View {
        List {
            // An empty summary from before the logs had issues must not hide the fresh digest.
            if let summary = logr.logIssueSummary, !summary.isEmpty {
                IssueTotalsSection(errors: summary.totalErrors, warnings: summary.totalWarnings,
                                   faults: summary.totalFaults, executiveSummary: summary.executiveSummary)
                TextListSection(title: "Priority Actions", items: summary.priorityActions, numbered: true)
                TextListSection(title: "Patterns Detected", items: summary.patterns, numbered: false)
                IssuesSection(rows: summary.issues.map { IssueRowModel(group: $0.group, issue: $0) })
            } else if let digest {
                IssueTotalsSection(errors: digest.totalErrors, warnings: digest.totalWarnings,
                                   faults: digest.totalFaults, executiveSummary: nil)
                if logr.canAnalyseLogs, !digest.isEmpty {
                    SummarizeSection {
                        requestCount += 1
                        request = Request(id: requestCount, reload: false)
                    }
                }
                IssuesSection(rows: digest.groups.map { IssueRowModel(group: $0, issue: nil) })
            }
        }
        .navigationTitle("Issue Summary")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if digest != nil || logr.logIssueSummary != nil {
                    Button("ReScan") {
                        requestCount += 1
                        request = Request(id: requestCount, reload: true)
                    }
                    .disabled(running != nil)
                }
            }
        }
        .overlay {
            if running?.explaining == true {
                AnalyzeProcessingView()
            } else if logr.logIssueSummary?.isEmpty ?? true, digest?.isEmpty == true {
                NoIssuesView()
            }
        }
        .task {
            digest = await logr.issueDigest()
        }
        .task(id: request) {
            guard let request else { return }
            starts += 1
            let start = starts
            running = Run(start: start, explaining: false)
            defer {
                if running?.start == start {
                    running = nil
                }
            }
            if request.reload {
                digest = await logr.issueDigest()
            }
            if !request.reload || logr.logIssueSummary != nil && logr.canAnalyseLogs {
                if running?.start == start {
                    running?.explaining = true
                }
                await summarize()
            }
            // `.task(id:)` runs again whenever the view reappears: a finished request must not.
            if !Task.isCancelled {
                self.request = nil
            }
        }
        .errorAlert(error: $showError)
    }

    private func summarize() async {
        do {
            try await logr.summarizeIssues()
        } catch is CancellationError {
            // Dismissed while summarizing.
        } catch {
            showError = error
        }
    }
}

private struct IssueRowModel: Identifiable {
    let group: LogIssueGroup
    let issue: LogIssue?

    var id: String {
        group.id
    }
}

private struct IssueTotalsSection: View {
    let errors: Int
    let warnings: Int
    let faults: Int
    let executiveSummary: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let badges = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 16))
        Section {
            VStack(alignment: .leading, spacing: 12) {
                if let executiveSummary {
                    Label("Executive Summary", systemImage: "chart.bar.doc.horizontal")
                        .font(.headline)
                    Text(executiveSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                badges {
                    StatBadgeView(count: errors, label: "Errors", color: LogLevel.error.tint)
                    StatBadgeView(count: warnings, label: "Warnings", color: LogLevel.warning.tint)
                    StatBadgeView(count: faults, label: "Faults", color: LogLevel.fault.tint)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

private struct SummarizeSection: View {
    let action: () -> Void

    var body: some View {
        Section {
            Button(action: action) {
                Label("Explain with Apple Intelligence", systemImage: "sparkles")
            }
        } footer: {
            Text("Adds a title, a likely cause and a fix to each issue, and an executive summary.")
        }
    }
}

private struct TextListSection: View {
    let title: LocalizedStringKey
    let items: [String]
    let numbered: Bool
    @ScaledMetric(relativeTo: .caption) private var numberSize = 24

    var body: some View {
        if !items.isEmpty {
            Section(title) {
                // Ids distinct from the other section's: macOS lists reuse rows by id across sections.
                let rows = items.enumerated().map {
                    (id: "\(numbered)-\($0.offset)", index: $0.offset, item: $0.element)
                }
                ForEach(rows, id: \.id) { _, index, item in
                    HStack(alignment: .firstTextBaseline) {
                        if numbered {
                            Text("\(index + 1)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .frame(width: numberSize, height: numberSize)
                                .background(index == 0 ? .red : index == 1 ? .orange : .blue)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .foregroundStyle(.blue)
                        }
                        Text(item)
                            .font(.subheadline)
                    }
                }
            }
        }
    }
}

private struct IssuesSection: View {
    let rows: [IssueRowModel]

    var body: some View {
        if !rows.isEmpty {
            Section("All Issues (\(rows.count))") {
                ForEach(rows) { row in
                    IssueRow(group: row.group, issue: row.issue)
                }
            }
        }
    }
}

struct IssueRow: View {
    let group: LogIssueGroup
    let issue: LogIssue?
    @State private var isExpanded = false

    var body: some View {
        LogDisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                if let explanation = issue?.explanation, !explanation.isEmpty {
                    IssueDetailRow(label: "Likely Cause", value: explanation)
                }
                IssueDetailRow(label: "Latest Message", value: group.sampleMessage)
                IssueDetailRow(label: "Location", value: "\(group.file):\(group.line)")
                    .monospaced()
                IssueDetailRow(label: "Last Seen",
                               value: group.lastSeen.formatted(date: .abbreviated, time: .standard))
                if let fix = issue?.suggestedFix, !fix.isEmpty {
                    IssueDetailRow(label: "Suggested Fix", value: fix)
                        .foregroundStyle(.blue)
                }
            }
        } label: {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                IssueRowLabel(group: group, issue: issue)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct IssueRowLabel: View {
    let group: LogIssueGroup
    let issue: LogIssue?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        layout {
            Image(systemName: group.level == .warning ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
                .foregroundStyle(group.level.tint)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(issue?.title ?? group.template)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("\(group.level.displayName) • \(group.category.rawValue) • \(group.count)×")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !dynamicTypeSize.isAccessibilitySize {
                Spacer()
            }

            if let issue {
                Text(issue.severity.description)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(issue.severity.tint.opacity(0.2))
                    .foregroundStyle(issue.severity.tint)
                    .cornerRadius(6)
            }
        }
        .contentShape(Rectangle())
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

private struct NoIssuesView: View {
    var body: some View {
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
                Text("Nothing to report here. Warnings, errors and faults show up here once they are logged.")
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

#Preview {
    @Previewable @State var mock = MockLogR()
    NavigationStack {
        IssueSummaryView()
    }
    .environment(\.logService, mock)
}
