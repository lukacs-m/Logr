//
//  ContentView.swift
//  LogRExample
//
//  Main hub view showcasing LogR library capabilities and quick actions.
//

import Logr
import SwiftUI

struct ContentView: View {
    @Environment(\.logService) private var logger

    @State private var isGenerating = false
    @State private var generationProgress = ""
    @State private var showClearConfirmation = false

    private var logCount: Int {
        logger.recentLogs.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                statsSection
                quickActionsSection
                mockDataSection
                featuresSection
            }
            .padding()
        }
        .navigationTitle("LogR Example")
        .confirmationDialog("Clear All Logs", isPresented: $showClearConfirmation) {
            Button("Clear All", role: .destructive) {
                Task {
                   try? await logger.clearLogs()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all stored logs.")
        }
        .onAppear {
            logger.info("ContentView appeared - Home tab loaded", category: .ui)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 60))
                .foregroundStyle(.blue.gradient)

            Text("LogR")
                .font(.largeTitle.bold())

            Text("Persistent logging with Apple OSLog")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical)
    }

    // MARK: - Stats

    private var statsSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                StatCard(
                    title: "Total Logs",
                    value: "\(logCount)",
                    icon: "doc.text.fill",
                    color: .blue
                )

                StatCard(
                    title: "In Memory",
                    value: "\(logger.recentLogs.count)",
                    icon: "memorychip.fill",
                    color: .green
                )
            }

            HStack(spacing: 12) {
                StatCard(
                    title: "Errors",
                    value: "\(countLogs(level: .error))",
                    icon: "exclamationmark.circle.fill",
                    color: .orange
                )

                StatCard(
                    title: "Faults",
                    value: "\(countLogs(level: .fault))",
                    icon: "xmark.octagon.fill",
                    color: .red
                )
            }
        }
    }

    private func countLogs(level: LogLevel) -> Int {
        logger.recentLogs.filter { $0.level == level }.count
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)

            HStack(spacing: 12) {
                ActionButton(
                    title: "Log Info",
                    icon: "info.circle.fill",
                    color: .blue
                ) {
                    logger.info("Quick info log from home", category: .ui)
                }

                ActionButton(
                    title: "Log Error",
                    icon: "exclamationmark.triangle.fill",
                    color: .orange
                ) {
                    logger.error("Quick error log from home", category: .debug)
                }

                ActionButton(
                    title: "Clear All",
                    icon: "trash.fill",
                    color: .red
                ) {
                    showClearConfirmation = true
                }
            }
        }
    }

    // MARK: - Mock Data Generation

    private var mockDataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Generate Mock Data")
                    .font(.headline)

                Spacer()

                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text("Generate realistic logs to explore LogViewer and AI Analysis features.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !generationProgress.isEmpty {
                Text(generationProgress)
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .transition(.opacity)
            }

            HStack(spacing: 12) {
                MockDataButton(
                    title: "Small",
                    subtitle: "500 logs",
                    icon: "1.circle.fill",
                    isDisabled: isGenerating
                ) {
                    await generateMockData(.small)
                }

                MockDataButton(
                    title: "Medium",
                    subtitle: "2,000 logs",
                    icon: "2.circle.fill",
                    isDisabled: isGenerating
                ) {
                    await generateMockData(.medium)
                }

                MockDataButton(
                    title: "Large",
                    subtitle: "5,000 logs",
                    icon: "3.circle.fill",
                    isDisabled: isGenerating
                ) {
                    await generateMockData(.large)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Includes:")
                    .font(.caption.bold())
                ForEach(mockDataFeatures, id: \.self) { feature in
                    Label(feature, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
    }

    private var mockDataFeatures: [String] {
        [
            "Normal operation logs (network, UI, database)",
            "Privacy issues (emails, tokens, PII) for AI scanning",
            "Error patterns for issue summarization",
            "Realistic app lifecycle events"
        ]
    }

    private enum DatasetSize {
        case small, medium, large
    }

    private func generateMockData(_ size: DatasetSize) async {
        isGenerating = true
        generationProgress = "Generating logs..."

        switch size {
        case .small:
            await MockDataGenerator.generateSmallDataset(logger: logger)
        case .medium:
            await MockDataGenerator.generateMediumDataset(logger: logger)
        case .large:
            await MockDataGenerator.generateLargeDataset(logger: logger)
        }

        generationProgress = "Complete!"
        try? await Task.sleep(for: .seconds(1.5))

        withAnimation {
            generationProgress = ""
            isGenerating = false
        }
    }

    // MARK: - Features Overview

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Features")
                .font(.headline)

            FeatureRow(
                icon: "square.and.pencil",
                title: "Log Demo",
                description: "Interactive logging at all levels and categories"
            )

            FeatureRow(
                icon: "list.bullet.rectangle",
                title: "Log Viewer",
                description: "Filter, search, and export logs with LogrUI"
            )

            FeatureRow(
                icon: "waveform.badge.magnifyingglass",
                title: "AI Analysis",
                description: "Privacy scanning and issue summarization (iOS 26+)"
            )

            FeatureRow(
                icon: "gear",
                title: "Settings",
                description: "Configuration, export options, and storage info"
            )
        }
    }
}

// MARK: - Supporting Views

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.title.bold())

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

private struct MockDataButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let isDisabled: Bool
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption.bold())
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    NavigationStack {
        ContentView()
    }
    .environment(\.logService, LogR())
}
