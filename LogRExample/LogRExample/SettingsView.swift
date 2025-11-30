//
//  SettingsView.swift
//  LogRExample
//
//  Displays configuration, export options, and storage information.
//

import Logr
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.logService) private var logger

    @State private var showExportSheet = false
    @State private var selectedExportFormat: ExportFormat = .json
    @State private var exportedFileURL: URL?
    @State private var showShareSheet = false
    @State private var showClearConfirmation = false
    @State private var exportError: String?

    var body: some View {
        List {
            configurationSection
            storageSection
            exportSection
            dangerZoneSection
            aboutSection
        }
        .navigationTitle("Settings")
        .confirmationDialog("Clear All Logs", isPresented: $showClearConfirmation) {
            Button("Clear All", role: .destructive) {
                Task {
                    try? await logger.clearLogs()
                    logger.info("All logs cleared by user", category: .system)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all \(logger.recentLogs.count) logs from storage.")
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedFileURL {
                ShareSheet(items: [url])
            }
        }
        .alert("Export Error", isPresented: .constant(exportError != nil)) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "Unknown error")
        }
        .onAppear {
            logger.debug("SettingsView appeared", category: .ui)
        }
    }

    // MARK: - Configuration

    @ViewBuilder
    private var configurationSection: some View {
        if let logr = logger as? LogR {
            Section {
                LabeledContent("Subsystem") {
                    Text(logr.configuration.subsystem)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Max Log Entries") {
                    Text("\(logr.configuration.maxLogEntries.formatted())")
                }

                LabeledContent("Max Log Age") {
                    Text(formatDuration(logr.configuration.maxLogAge))
                }

                LabeledContent("Cleanup Interval") {
                    Text(formatDuration(logr.configuration.cleanupInterval))
                }

                LabeledContent("Verbosity") {
                    Text(logr.configuration.logVerbosity == .verbose ? "Verbose" : "Normal")
                }

                DisclosureGroup("Enabled Levels (\(logr.configuration.enabledLevels.count))") {
                    ForEach(LogLevel.allCases) { level in
                        HStack {
                            Text(level.visualQueue)
                            Text(level.displayName)
                            Spacer()
                            if logr.configuration.enabledLevels.contains(level) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Configuration")
            } footer: {
                Text("Current logger configuration. Modify in LogRExampleApp.swift.")
            }
        }
    }

    // MARK: - Storage

    private var storageSection: some View {
        Section {
            LabeledContent("Logs in Memory") {
                Text("\(logger.recentLogs.count.formatted())")
            }

            LabeledContent("Errors") {
                Text("\(countLogs(level: .error).formatted())")
                    .foregroundStyle(.orange)
            }

            LabeledContent("Warnings") {
                Text("\(countLogs(level: .warning).formatted())")
                    .foregroundStyle(.yellow)
            }

            LabeledContent("Faults") {
                Text("\(countLogs(level: .fault).formatted())")
                    .foregroundStyle(.red)
            }

            LabeledContent("Debug Logs") {
                Text("\(countLogs(level: .debug).formatted())")
                    .foregroundStyle(.purple)
            }
        } header: {
            Text("Storage Status")
        } footer: {
            Text("Logs are encrypted at rest using AES-256-GCM with Keychain-stored keys.")
        }
    }

    private func countLogs(level: LogLevel) -> Int {
        logger.recentLogs.count(where: { $0.level == level })
    }

    // MARK: - Export

    private var exportSection: some View {
        Section {
            Picker("Export Format", selection: $selectedExportFormat) {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    Text(format.formatName).tag(format)
                }
            }

            Button {
                exportLogs()
            } label: {
                Label("Export Logs", systemImage: "square.and.arrow.up")
            }
            .disabled(logger.recentLogs.isEmpty)

            if let url = exportedFileURL {
                HStack {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading) {
                        Text("Export Ready")
                            .font(.caption.bold())
                        Text(url.lastPathComponent)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Share") {
                        showShareSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        } header: {
            Text("Export")
        } footer: {
            Text("Export logs in JSON (structured), CSV (spreadsheet), or TXT (readable) format.")
        }
    }

    private func exportLogs() {
        guard let data = logger.exportLogs(format: selectedExportFormat) else {
            exportError = "Failed to export logs"
            return
        }

        let fileExtension = switch selectedExportFormat {
        case .json: "json"
        case .csv: "csv"
        case .txt: "txt"
        }

        let filename = "logr_export_\(Date().ISO8601Format()).\(fileExtension)"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: tempURL)
            exportedFileURL = tempURL
            logger.info("Logs exported successfully: \(filename)", category: .fileSystem)
        } catch {
            exportError = "Failed to save export: \(error.localizedDescription)"
            logger.error("Export failed: \(error.localizedDescription)", category: .fileSystem)
        }
    }

    // MARK: - Danger Zone

    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                showClearConfirmation = true
            } label: {
                Label("Clear All Logs", systemImage: "trash.fill")
            }
            .disabled(logger.recentLogs.isEmpty)
        } header: {
            Text("Danger Zone")
        } footer: {
            Text("This action cannot be undone. All logs will be permanently deleted.")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            LabeledContent("LogR Version") {
                Text("1.0.0")
            }

            LabeledContent("Platforms") {
                Text("iOS 17+, macOS 14+")
            }

            LabeledContent("Swift") {
                Text("6.0+")
            }

            DisclosureGroup("Features") {
                featureItem("OSLog Integration", icon: "apple.terminal.fill")
                featureItem("SQLite Persistence", icon: "externaldrive.fill")
                featureItem("AES-256 or CHACHA Encryption", icon: "lock.shield.fill")
                featureItem("SwiftUI Log Viewer", icon: "list.bullet.rectangle")
                featureItem("AI Analysis (iOS 26+)", icon: "brain")
                featureItem("Export (JSON/CSV/TXT)", icon: "square.and.arrow.up")
            }
        } header: {
            Text("About LogR")
        }
    }

    private func featureItem(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption)
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3_600
        let minutes = (Int(seconds) % 3_600) / 60

        if hours >= 24 {
            let days = hours / 24
            return "\(days) day\(days == 1 ? "" : "s")"
        } else if hours > 0 {
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        } else {
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        }
    }
}

// MARK: - Share Sheet

#if os(iOS)
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
private struct ShareSheet: View {
    let items: [Any]

    var body: some View {
        if let url = items.first as? URL {
            VStack(spacing: 16) {
                Image(systemName: "doc.fill")
                    .font(.largeTitle)
                Text("Export Ready")
                    .font(.headline)
                Text(url.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}
#endif

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(\.logService, LogR())
}
