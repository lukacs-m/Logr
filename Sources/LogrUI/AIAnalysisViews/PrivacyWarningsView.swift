import Logr
import SwiftUI

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
public struct PrivacyWarningsView: View {
    @Environment(\.logService) var logr
    @State private var loading = false
    @State private var showError: Error?
    
    public init() {}
    
    public var body: some View {
        mainContent
            .navigationTitle("Privacy Warnings")
            .overlay {
                overlayContent
            }
            .task {
                await loadData()
            }
            .errorAlert(error: $showError)
    }
    
    private func severityBadge(count: Int, severity: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(count) \(severity)")
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func loadData() async {
        defer { loading = false }
        
        do {
            if logr.privacyAnalysisResult == nil {
                loading = true
            }
            try await logr.scanForPrivacyIssues()
        } catch {
            showError = error
        }
    }
}

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
private extension PrivacyWarningsView {
    var mainContent: some View {
        List {
            analysisSections
            warningSections
        }
    }
    
    @ViewBuilder
    var analysisSections: some View {
        if let privacyAnalysis = logr.privacyAnalysisResult {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: privacyAnalysis.isEmpty ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .foregroundStyle(privacyAnalysis.isEmpty ? .green : .red)
                        .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Privacy Analysis")
                                .font(.headline)
                            Text(privacyAnalysis.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    if privacyAnalysis.criticalCount > 0 || privacyAnalysis.highCount > 0 {
                        HStack(spacing: 16) {
                            if privacyAnalysis.criticalCount > 0 {
                                severityBadge(count: privacyAnalysis.criticalCount,
                                              severity: "Critical",
                                              color: .red)
                            }
                            if privacyAnalysis.highCount > 0 {
                                severityBadge(count: privacyAnalysis.highCount,
                                              severity: "High",
                                              color: .orange)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
    
    @ViewBuilder
    var warningSections: some View {
        if let privacyAnalysis = logr.privacyAnalysisResult, !privacyAnalysis.warnings.isEmpty {
            ForEach(privacyAnalysis.warnings) { warning in
                Section {
                    PrivacyWarningRow(warning: warning)
                }
            }
        }
    }
}

// MARK: - Overlay
@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
private extension PrivacyWarningsView {
    @ViewBuilder
    var overlayContent: some View {
        if loading {
            AnalyzeProcessingView()
        } else if let privacyAnalysis = logr.privacyAnalysisResult, privacyAnalysis.isEmpty {
            ContentUnavailableView {
                Image(systemName: "text.page.badge.magnifyingglass")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 210, height: 120)
                    .padding(.bottom, 16)
            } description: {
                VStack(spacing: 8) {
                    Text("No Privacy issues found in your logs")
                        .font(.title2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .top)
                        .opacity(0.9)
                    Text("Nothing to report here. It seems your are not exposing any sensitive user information.")
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
private struct PrivacyWarningRow: View {
    let warning: PrivacyWarning
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                severityIcon
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(warning.exposureType.capitalized)
                        .font(.headline)
                    Text("\(warning.file):\(warning.line)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospaced()
                }
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                PrivacyDetailRow(label: "Exposed", value: warning.exposedContent)
                    .font(.caption)
                    .padding(8)
                    .background(Color.red.opacity(0.05))
                    .cornerRadius(6)
                
                PrivacyDetailRow(label: "Explanation", value: warning.explanation)
                
                PrivacyDetailRow(label: "Recommendation", value: warning.recommendation)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var severityIcon: some View {
        switch warning.severity.lowercased() {
        case "critical":
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case "high":
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        case "medium":
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.yellow)
        default:
            Image(systemName: "info.circle")
                .foregroundStyle(.blue)
        }
    }
}

struct PrivacyDetailRow: View {
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
    @Previewable @State var mock = MockLogR()
    NavigationStack {
        PrivacyWarningsView()
    }
    .environment(\.logService, mock)
}
