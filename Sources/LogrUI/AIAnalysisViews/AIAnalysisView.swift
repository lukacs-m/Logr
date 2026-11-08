import Logr
import SwiftUI

public struct AIAnalysisView: View {
    @Environment(\.logService) private var logr
    @State private var analysisState: AnalysisState = .idle

    // MARK: - Analysis State

    private enum AnalysisState: Equatable {
        case idle
        case privacyComplete
        case issuesComplete
    }

    public init() {}

    public var body: some View {
        mainContent
            .navigationTitle("Log Analysis")
    }

    @ViewBuilder
    var mainContent: some View {
        switch analysisState {
        case .idle:
            idleView
        case .privacyComplete:
            PrivacyWarningsView()
        case .issuesComplete:
            IssueSummaryView()
        }
    }

    private var idleView: some View {
        ScrollView {
            idleContent
        }
    }

    private var idleContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "cpu.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text("Review Your Logs")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text("Find sensitive values in your logs and review recurring problems")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 16) {
                AnalysisActionButton(title: "Scan for Privacy Issues",
                                     subtitle: "Detect exposed PII, credentials, and sensitive data",
                                     icon: "eye.trianglebadge.exclamationmark.fill",
                                     color: .red) {
                    // The privacy view scans when it appears.
                    analysisState = .privacyComplete
                }
                .disabled(logr.recentLogs.isEmpty)

                AnalysisActionButton(title: "Summarize Issues",
                                     subtitle: "Errors grouped by call site, explained by Apple Intelligence when available",
                                     icon: "chart.bar.doc.horizontal.fill",
                                     color: .blue) {
                    analysisState = .issuesComplete
                }
                .disabled(logr.recentLogs.isEmpty)
            }
            .padding(.horizontal)

            if logr.recentLogs.isEmpty {
                Text("No logs available to analyze")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top)
            } else {
                Text("\(logr.recentLogs.count) log entries ready for analysis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top)
            }
        }
        .padding()
    }
}

private struct AnalysisActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 16))
        Button(action: action) {
            layout {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(minWidth: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.fill.tertiary, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Analyzing State") {
    @Previewable @State var mock = MockLogR()
    NavigationStack {
        AIAnalysisView()
            .environment(\.logService, mock)
    }
}
