//
//  LogAnalysisView.swift
//  LogRExample
//
//  Showcases the AI-powered log analysis features (iOS 26+).
//

import Logr
import LogrUI
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
struct LogAnalysisView: View {
    @Environment(\.logService) private var logger

    @State private var privacyResult: PrivacyAnalysisResult?
    @State private var issueSummary: LogIssueSummary?
    @State private var isAnalyzingPrivacy = false
    @State private var isAnalyzingIssues = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            aiAvailabilitySection
            privacyAnalysisSection
            issueSummarySection
            resultsSection
        }
        .navigationTitle("Log Analysis")
        .alert("Analysis Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - AI Availability

    private var aiAvailabilitySection: some View {
        Section {
            if #available(iOS 26.0, macOS 26.0, *) {
                Label {
                    VStack(alignment: .leading) {
                        Text("AI Analysis Available")
                            .font(.headline)
                        Text("Apple Intelligence features are supported on this device.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } else {
                Label {
                    VStack(alignment: .leading) {
                        Text("AI Analysis Unavailable")
                            .font(.headline)
                        Text("Requires iOS 26+ with Apple Intelligence.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("Status")
        } footer: {
            Text("AI analysis uses on-device Apple Intelligence for privacy scanning and issue summarization.")
        }
    }

    // MARK: - Privacy Analysis

    private var privacyAnalysisSection: some View {
        Section {
            if #available(iOS 26.0, macOS 26.0, *) {
                Button {
                    Task { await runPrivacyAnalysis() }
                } label: {
                    HStack {
                        Label("Scan for Privacy Issues", systemImage: "shield.checkered")
                        Spacer()
                        if isAnalyzingPrivacy {
                            Text("\(logger.analysisProgress?.percentComplete)%")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .contentTransition(.numericText())
                            ProgressView()
                        }
                    }
                }
                .disabled(isAnalyzingPrivacy)
            } else {
                Label("Privacy scanning requires iOS 26+", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Privacy Analysis")
        } footer: {
            Text("Scans logs for potential PII exposure: emails, phone numbers, API keys, tokens, and other sensitive data.")
        }
    }

    // MARK: - Issue Summary

    private var issueSummarySection: some View {
        Section {
            if #available(iOS 26.0, macOS 26.0, *) {
                Button {
                    Task { await runIssueSummary() }
                } label: {
                    HStack {
                        Label("Summarize Issues", systemImage: "doc.text.magnifyingglass")
                        Spacer()
                        if isAnalyzingIssues {
                            Text("\(logger.analysisProgress?.percentComplete)%")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .contentTransition(.numericText())
                            ProgressView()
                        }
                    }
                }
                .disabled(isAnalyzingIssues)
            } else {
                Label("Issue summary requires iOS 26+", systemImage: "doc.text")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Issue Summary")
        } footer: {
            Text("Analyzes errors, warnings, and patterns to provide actionable insights and recommendations.")
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsSection: some View {
        if let privacy = privacyResult {
            Section {
                privacyScoreCard(privacy)

                if !privacy.warnings.isEmpty {
                    DisclosureGroup("Warnings (\(privacy.warnings.count))") {
                        ForEach(privacy.warnings.indices, id: \.self) { index in
                            privacyWarningRow(privacy.warnings[index])
                        }
                    }
                }

                if !privacy.summary.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Summary")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(privacy.summary)
                            .font(.callout)
                    }
                }
            } header: {
                HStack {
                    Text("Privacy Results")
                    Spacer()
                    Button("Clear") {
                        privacyResult = nil
                    }
                    .font(.caption)
                }
            }
        }

        if let summary = issueSummary {
            Section {
                issueSummaryCard(summary)

                if !summary.executiveSummary.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Executive Summary")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(summary.executiveSummary)
                            .font(.callout)
                    }
                }

                if !summary.priorityActions.isEmpty {
                    DisclosureGroup("Priority Actions (\(summary.priorityActions.count))") {
                        ForEach(summary.priorityActions.indices, id: \.self) { index in
                            Label(summary.priorityActions[index], systemImage: "\(index + 1).circle.fill")
                                .font(.callout)
                        }
                    }
                }

                if !summary.patterns.isEmpty {
                    DisclosureGroup("Detected Patterns (\(summary.patterns.count))") {
                        ForEach(summary.patterns.indices, id: \.self) { index in
                            Text(summary.patterns[index])
                                .font(.callout)
                        }
                    }
                }

                if !summary.issues.isEmpty {
                    DisclosureGroup("Issues (\(summary.issues.count))") {
                        ForEach(summary.issues.indices, id: \.self) { index in
                            issueRow(summary.issues[index])
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Issue Summary Results")
                    Spacer()
                    Button("Clear") {
                        issueSummary = nil
                    }
                    .font(.caption)
                }
            }
        }
    }

    // MARK: - Cards & Rows

    private func privacyScoreCard(_ result: PrivacyAnalysisResult) -> some View {
        HStack(spacing: 16) {
            VStack {
                Text("\(result.criticalCount)")
                    .font(.title.bold())
                    .foregroundStyle(.red)
                Text("Critical")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack {
                Text("\(result.highCount)")
                    .font(.title.bold())
                    .foregroundStyle(.orange)
                Text("High")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack {
                Text("\(result.warnings.count)")
                    .font(.title.bold())
                    .foregroundStyle(.yellow)
                Text("Total")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func privacyWarningRow(_ warning: PrivacyWarning) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(warning.exposureType)
                    .font(.headline)
                Spacer()
                Text(warning.severity)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(severityColor(warning.severity).opacity(0.2), in: Capsule())
                    .foregroundStyle(severityColor(warning.severity))
            }

            Text("\(warning.file):\(warning.line)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            if !warning.explanation.isEmpty {
                Text(warning.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !warning.recommendation.isEmpty {
                Text(warning.recommendation)
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
    }

    private func issueSummaryCard(_ summary: LogIssueSummary) -> some View {
        HStack(spacing: 16) {
            VStack {
                Text("\(summary.totalFaults)")
                    .font(.title.bold())
                    .foregroundStyle(.red)
                Text("Faults")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack {
                Text("\(summary.totalErrors)")
                    .font(.title.bold())
                    .foregroundStyle(.orange)
                Text("Errors")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack {
                Text("\(summary.totalWarnings)")
                    .font(.title.bold())
                    .foregroundStyle(.yellow)
                Text("Warnings")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func issueRow(_ issue: LogIssue) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(issue.title)
                    .font(.headline)
                Spacer()
                Text(issue.severity)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(severityColor(issue.severity).opacity(0.2), in: Capsule())
                    .foregroundStyle(severityColor(issue.severity))
            }

            Text(issue.category)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(issue.description)
                .font(.callout)

            if issue.occurrences > 1 {
                Text("Occurred \(issue.occurrences) times")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !issue.suggestedFix.isEmpty {
                Text("Suggested Fix: \(issue.suggestedFix)")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
    }

    private func severityColor(_ severity: String) -> Color {
        switch severity.lowercased() {
        case "critical", "fault": .red
        case "error", "high": .orange
        case "medium", "warning": .yellow
        default: .secondary
        }
    }

    // MARK: - Analysis Methods

    @available(iOS 26.0, macOS 26.0, *)
    private func runPrivacyAnalysis() async {
        isAnalyzingPrivacy = true
        defer { isAnalyzingPrivacy = false }

        do {
            privacyResult = try await logger.scanForPrivacyIssues()
            logger.info("Privacy analysis completed", category: .analytics)
        } catch {
            errorMessage = "Privacy analysis failed: \(error.localizedDescription)"
            logger.error("Privacy analysis failed: \(error.localizedDescription)", category: .analytics)
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func runIssueSummary() async {
        isAnalyzingIssues = true
        defer { isAnalyzingIssues = false }

        do {
            issueSummary = try await logger.summarizeIssues()
            logger.info("Issue summary completed", category: .analytics)
        } catch {
            errorMessage = "Issue summary failed: \(error.localizedDescription)"
            logger.error("Issue summary failed: \(error.localizedDescription)", category: .analytics)
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
#Preview {
    NavigationStack {
        LogAnalysisView()
    }
    .environment(\.logService, LogR())
}
