import Logr
import SwiftUI

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
public struct PrivacyWarningsView: View {
    let result: PrivacyAnalysisResult

    public init(result: PrivacyAnalysisResult) {
        self.result = result
    }

    public var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: result.warnings
                            .isEmpty ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .foregroundStyle(result.warnings.isEmpty ? .green : .red)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Privacy Analysis")
                                .font(.headline)
                            Text(result.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if result.criticalCount > 0 || result.highCount > 0 {
                        HStack(spacing: 16) {
                            if result.criticalCount > 0 {
                                severityBadge(count: result.criticalCount, severity: "Critical", color: .red)
                            }
                            if result.highCount > 0 {
                                severityBadge(count: result.highCount, severity: "High", color: .orange)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.vertical, 8)
            }

            if !result.warnings.isEmpty {
                ForEach(result.warnings) { warning in
                    Section {
                        PrivacyWarningRow(warning: warning)
                    }
                }
            }
        }
        .navigationTitle("Privacy Warnings")
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
}

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
struct PrivacyWarningRow: View {
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
        Group {
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
    NavigationStack {
        PrivacyWarningsView(result: PrivacyAnalysisResult(warnings: [
                PrivacyWarning(file: "LoginViewController.swift",
                               line: 42,
                               exposureType: "email",
                               exposedContent: "user@example.com",
                               explanation: "Email address is being logged in plain text, which could expose user identity.",
                               severity: "high",
                               recommendation: "Remove email logging or use hashed/redacted versions."),
                PrivacyWarning(file: "PaymentService.swift",
                               line: 158,
                               exposureType: "credit card",
                               exposedContent: "4532-1234-5678-1234",
                               explanation: "Full credit card number detected in logs - severe PCI compliance violation.",
                               severity: "critical",
                               recommendation: "Never log credit card numbers. Implement PCI-DSS compliant logging.")
            ],
            summary: "Found 2 potential privacy exposures: 1 critical, 1 high severity.",
            criticalCount: 1,
            highCount: 1))
    }
}
