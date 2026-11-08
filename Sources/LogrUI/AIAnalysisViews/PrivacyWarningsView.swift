import Logr
import SwiftUI

/// Lists the values `LogRService.scanForPrivacyIssues()` found, one row per call site and detector.
public struct PrivacyWarningsView: View {
    @Environment(\.logService) var logr
    @State private var loading = false
    /// This view's own scan, run each time it appears so new logs are included: a service may not publish its
    /// result (``LogRService`` has a default implementation).
    @State private var scanned: PrivacyAnalysisResult?

    private var result: PrivacyAnalysisResult? {
        scanned ?? logr.privacyAnalysisResult
    }

    public init() {}

    public var body: some View {
        List {
            if let result {
                PrivacySummarySection(result: result)
                ForEach(result.warnings) { warning in
                    Section {
                        PrivacyWarningRow(warning: warning)
                    }
                }
            }
        }
        .navigationTitle("Privacy Warnings")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if result != nil {
                    Button("ReScan") {
                        Task { await scan() }
                    }
                    .disabled(loading)
                }
            }
        }
        .overlay {
            if loading {
                ProgressView("Scanning logs…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
            } else if let result, result.isEmpty {
                NoPrivacyIssuesView()
            }
        }
        .task {
            await scan()
        }
    }

    private func scan() async {
        loading = true
        defer { loading = false }
        scanned = await logr.scanForPrivacyIssues()
    }
}

private struct PrivacySummarySection: View {
    let result: PrivacyAnalysisResult
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let header = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout())
        let badges = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 16))
        Section {
            VStack(alignment: .leading, spacing: 8) {
                header {
                    Image(systemName: result.isEmpty ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .foregroundStyle(result.isEmpty ? .green : .red)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Privacy Scan")
                            .font(.headline)
                        Text(result.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if result.criticalCount > 0 || result.highCount > 0 {
                    badges {
                        if result.criticalCount > 0 {
                            SeverityCountBadge(count: result.criticalCount, severity: .critical)
                        }
                        if result.highCount > 0 {
                            SeverityCountBadge(count: result.highCount, severity: .high)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 8)
        } footer: {
            if !result.isEmpty {
                Text("Interpolate these values with privacy: .private or .sensitive, or stop logging them.")
            }
        }
    }
}

private struct SeverityCountBadge: View {
    let count: Int
    let severity: LogSeverity

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(severity.tint)
                .frame(width: 8, height: 8)
            Text("\(count) \(severity.description)")
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(severity.tint.opacity(0.1))
        .cornerRadius(8)
    }
}

private struct PrivacyWarningRow: View {
    let warning: PrivacyWarning
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let header = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        VStack(alignment: .leading, spacing: 12) {
            header {
                Image(systemName: warning.severity.symbolName)
                    .foregroundStyle(warning.severity.tint)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(warning.detector)
                        .font(.headline)
                    Text("\(warning.file):\(warning.line)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospaced()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                PrivacyDetailRow(label: warning.field == "message" ? "Message" : "Metadata \(warning.field)",
                                 value: warning.excerpt)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.05))
                    .cornerRadius(6)

                Text(warning.occurrences == 1 ? "1 occurrence" : "\(warning.occurrences) occurrences")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
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

private struct NoPrivacyIssuesView: View {
    var body: some View {
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
                Text("Nothing to report here. It seems you are not exposing any sensitive user information.")
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
        PrivacyWarningsView()
    }
    .environment(\.logService, mock)
}
