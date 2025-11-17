import Logr
import SwiftUI

//TODO: get env key for logr
@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
public struct AIAnalysisView: View {
    let logs: [LogEntry]
    let analyzer: LogAIAnalyzer

    @State private var analysisState: AnalysisState = .idle
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    public init(logs: [LogEntry], analyzer: LogAIAnalyzer = AIAnalyzer()) {
        self.logs = logs
        self.analyzer = analyzer
    }

    public var body: some View {
        Group {
            switch analysisState {
            case .idle:
                idleView
            case .analyzing:
                analyzingView
            case let .privacyComplete(result):
                PrivacyWarningsView(result: result)
            case let .issuesComplete(summary):
                IssueSummaryView(summary: summary)
            }
        }
        .navigationTitle("AI Analysis")
        .alert("Analysis Error", isPresented: $showError) {
            Button("OK") { analysisState = .idle }
        } message: {
            Text(errorMessage)
        }
        .task {
            checkAvailability()
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

            if logs.isEmpty {
                Text("No logs available to analyze")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top)
            } else {
                Text("\(logs.count) log entries ready for analysis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top)
            }
        }
        .padding()
    }

    private var analyzingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)

            VStack(spacing: 8) {
                Text("Analyzing Logs")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Apple Intelligence is processing your logs...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
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
        .disabled(logs.isEmpty || analysisState == .analyzing)
    }

    // MARK: - Analysis Actions

    private func checkAvailability() {
        let available = analyzer.isAvailable
        if !available {
            errorMessage = "Apple Intelligence is not available on this device. Requires iOS 18+, macOS 15+, or later."
            showError = true
        }
    }

    private func scanPrivacy() async {
        guard !logs.isEmpty else { return }

        analysisState = .analyzing

        do {
            let result = try await analyzer.scanForPrivacyIssues(logs: logs)
            analysisState = .privacyComplete(result)
        } catch {
            handleError(error)
        }
    }

    private func summarizeIssues() async {
        guard !logs.isEmpty else { return }

        analysisState = .analyzing

        do {
            let summary = try await analyzer.summarizeIssues(logs: logs)
            analysisState = .issuesComplete(summary)
        } catch {
            handleError(error)
        }
    }

    private func handleError(_ error: Error) {
        if let aiError = error as? AIAnalyzerError {
            errorMessage = aiError.localizedDescription
        } else {
            errorMessage = "An unexpected error occurred: \(error.localizedDescription)"
        }
        showError = true
        analysisState = .idle
    }
}

// MARK: - Analysis State

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
enum AnalysisState: Equatable {
    case idle
    case analyzing
    case privacyComplete(PrivacyAnalysisResult)
    case issuesComplete(LogIssueSummary)
}

// MARK: - Preview

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
#Preview("Idle State") {
    NavigationStack {
        AIAnalysisView(logs: [
            LogEntry(level: .error,
                     category: .system,
                     subsystem: "com.example.app",
                     message: "User email: user@example.com failed to authenticate",
                     file: "LoginViewController.swift",
                     line: 42),
            LogEntry(level: .error,
                     category: .network,
                     subsystem: "com.example.app",
                     message: "Network request timeout",
                     file: "NetworkManager.swift",
                     line: 156)
        ])
    }
}

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
#Preview("Analyzing State") {
    NavigationStack {
        AIAnalysisView(logs: [])
    }
}
