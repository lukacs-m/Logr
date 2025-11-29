import Logr
import SwiftUI

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
public struct AIAnalysisView: View {
    @Environment(\.logService) private var logr
    @State private var analysisState: AnalysisState = .idle
    @State private var showError: Error?

    // MARK: - Analysis State

    private enum AnalysisState: Equatable {
        case idle
        case analyzing
        case privacyComplete
        case issuesComplete
    }

    private enum AIAnalysisViewError: LocalizedError {
        case analysisInitError
        case analysisError(String)

        var errorDescription: String? {
            switch self {
            case .analysisInitError:
                "Apple Intelligence is not available on this device. Requires iOS 26+, macOS 26+, or later."
            case let .analysisError(message):
                message
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .analysisError, .analysisInitError:
                "Analysis Error"
            }
        }
    }

    public init() {}

    public var body: some View {
        mainContent
            .navigationTitle("AI Analysis")
            .errorAlert(error: $showError)
            .task {
                checkAvailability()
            }
    }

    @ViewBuilder
    var mainContent: some View {
        switch analysisState {
        case .idle:
            idleView
        case .analyzing:
            AnalyzeProcessingView()
        case .privacyComplete:
            PrivacyWarningsView()
        case .issuesComplete:
            IssueSummaryView()
        }
    }

    private var idleView: some View {
        VStack(spacing: 24) {
            Image(systemName: "cpu.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text("AI-Powered Log Analysis")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Use Apple Intelligence to analyze logs for privacy issues and potential problems")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 16) {
                analyzeButton(title: "Scan for Privacy Issues",
                              subtitle: "Detect exposed PII, credentials, and sensitive data",
                              icon: "eye.trianglebadge.exclamationmark.fill",
                              color: .red) {
                    await scanPrivacy()
                }

                analyzeButton(title: "Summarize Issues",
                              subtitle: "Identify errors, patterns, and actionable insights",
                              icon: "chart.bar.doc.horizontal.fill",
                              color: .blue) {
                    await summarizeIssues()
                }
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

    private func analyzeButton(title: String,
                               subtitle: String,
                               icon: String,
                               color: Color,
                               action: @escaping () async -> Void) -> some View {
        Button {
            Task {
                await action()
            }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding()
            .background(.secondary)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .disabled(logr.recentLogs.isEmpty || analysisState == .analyzing)
    }

    // MARK: - Analysis Actions

    private func checkAvailability() {
        if !logr.canAnalyseLogs {
            showError = AIAnalysisViewError.analysisInitError
        }
    }

    private func scanPrivacy() async {
        guard !logr.recentLogs.isEmpty else { return }

        analysisState = .analyzing

        do {
            try await logr.scanForPrivacyIssues()
            analysisState = .privacyComplete
        } catch {
            handleError(error)
        }
    }

    private func summarizeIssues() async {
        guard !logr.recentLogs.isEmpty else { return }

        analysisState = .analyzing

        do {
            try await logr.summarizeIssues()
            analysisState = .issuesComplete
        } catch {
            handleError(error)
        }
    }

    private func handleError(_ error: Error) {
        let errorMessage = if let error = error as? AIAnalyzerError {
            error.localizedDescription
        } else {
            "An unexpected error occurred: \(error.localizedDescription)"
        }
        showError = AIAnalysisViewError.analysisError(errorMessage)
        analysisState = .idle
    }
}

 // MARK: - Preview

 @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
 #Preview("Analyzing State") {
    @Previewable @State var mock = MockLogR()
    NavigationStack {
        AIAnalysisView()
            .environment(\.logService, mock)
    }
 }
