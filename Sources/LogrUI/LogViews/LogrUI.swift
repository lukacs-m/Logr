//
//  LogrUI.swift
//  Logr
//
//  Created by martin on 01/11/2025.
//

import Combine
import Logr
import SwiftUI
import UniformTypeIdentifiers

public struct LogViewer: View {
    @Environment(\.logService) private var logr
    @State private var showingDeleteConfirmation = false
    @State private var shareItem: ShareItem?
    @State private var presentedSheet: SheetDestination?
    @State private var selectedLevels: Set<LogLevel> = Set(LogLevel.allCases)
    @State private var selectedCategories: Set<LogCategory> = []
    @State private var allExpanded = false
    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var showError: Error?

    enum SheetDestination: Identifiable {
        case filters
        case export
        case privacyLogChecks
        case issuesSummary

        var id: Self { self }
    }

    enum LogViewerError: LocalizedError {
        case failedLogClearing

        var errorDescription: String? {
            switch self {
            case .failedLogClearing:
                "Failed to clear logs"
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .failedLogClearing:
                "Article publishing failed due to missing title"
            }
        }
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            mainContent
        }
        .errorAlert(error: $showError)
        .sheet(item: $presentedSheet) { destination in
            sheetView(destination: destination)
        }
        .confirmationDialog("Clear All Logs",
                            isPresented: $showingDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Clear All Logs", role: .destructive) {
                clearAllLogs()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all stored log entries. This action cannot be undone.")
        }
    }

    @ViewBuilder
    private func sheetView(destination: SheetDestination) -> some View {
        switch destination {
        case .export:
            ExportSheet()
        case .filters:
            FilterSheet(selectedLevels: $selectedLevels,
                        selectedCategories: $selectedCategories)
        case .privacyLogChecks:
            if #available(iOS 26.0, macOS 26.0, *) {
                NavigationStack {
                    PrivacyWarningsView()
                }
            } else {
                NonAccessibleFeatureView()
            }
        case .issuesSummary:
            if #available(iOS 26.0, macOS 26.0, *) {
                NavigationStack {
                    IssueSummaryView()
                }
            } else {
                NonAccessibleFeatureView()
            }
        }
    }

    private var filteredLogs: [LogEntry] {
        filterData()
    }
}

// MARK: - Main Content View

private extension LogViewer {
    var mainContent: some View {
        List {
            ForEach(filteredLogs) { entry in
                LogEntryRow(entry: entry, displayState: $allExpanded)
                    .equatable()
            }
        }
        .searchable(text: $searchText, prompt: "Search logs...")
        .task(id: searchText) {
            // Skip debounce for empty string (immediate clear)
            if searchText.isEmpty {
                debouncedQuery = ""
                return
            }
            // Debounce
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            debouncedQuery = searchText
        }
        .navigationTitle("LogR Viewer")
        .toolbar {
            toolbarContent
        }
        .overlay {
            overlayContent
        }
    }
}

// MARK: - Overlay

private extension LogViewer {
    @ViewBuilder
    var overlayContent: some View {
        if filteredLogs.isEmpty, !searchText.isEmpty {
            VStack(spacing: 20) {
                Spacer()
                Text("Couldn't find any logs corresponding to your search criteria \"\(searchText)\"")
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text("Try searching using different spelling or keywords")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal)
        } else if filteredLogs.isEmpty, debouncedQuery.isEmpty {
            ContentUnavailableView {
                Image(systemName: "text.page.badge.magnifyingglass")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 210, height: 120)
                    .padding(.bottom, 16)
            } description: {
                VStack(spacing: 8) {
                    Text("No logs available yet")
                        .font(.title2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .top)
                        .opacity(0.9)
                    Text("Protect your accounts with an extra layer of security.")
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

// MARK: - Toolbar actions

private extension LogViewer {
    var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Filters") {
                presentedSheet = .filters
            }
            .disabled(logr.recentLogs.isEmpty)

            Menu {
                Button(allExpanded ? "Collapse All" : "Expand All") {
                    allExpanded.toggle()
                }
                .disabled(logr.recentLogs.isEmpty)

                Divider()

                logAnalyzeMenu

                shareMenu

                Button("Clear All Logs", role: .destructive) {
                    showingDeleteConfirmation = true
                }
                .disabled(logr.recentLogs.isEmpty)

            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .disabled(logr.recentLogs.isEmpty)
        }
    }

    @ViewBuilder
    var logAnalyzeMenu: some View {
        if logr.canAnalyseLogs {
            Menu {
                Button {
                    presentedSheet = .privacyLogChecks
                } label: {
                    Label {
                        Text("Scan for Privacy Issues")
                    } icon: {
                        Image(systemName: "eye.trianglebadge.exclamationmark.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .red)
                    }
                }
                .disabled(logr.recentLogs.isEmpty)

                Button {
                    presentedSheet = .issuesSummary
                } label: {
                    Label {
                        Text("Summarize Issues")
                    } icon: {
                        Image(systemName: "chart.bar.doc.horizontal.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.blue)
                    }
                }
                .disabled(logr.recentLogs.isEmpty)
            } label: {
                Text("Analyze logs")
            }
            .disabled(logr.recentLogs.isEmpty)
            Divider()
        }
    }

    @ViewBuilder
    var shareMenu: some View {
        if !logr.recentLogs.isEmpty {
            Menu("Export & Share") {
                ForEach(ExportFormat.allCases) { format in
                    let fileName = format.formatName
                    ShareLink(item: prepareShareItem(format: format, fileName: fileName),
                              preview: SharePreview("LogR Export")) {
                        Label("Share \(fileName)", systemImage: "square.and.arrow.up")
                    }
                }

                Divider()

                Button {
                    presentedSheet = .export
                } label: {
                    Label("Export to Files", systemImage: "folder.fill")
                }
            }
            Divider()
        }
    }
}

// MARK: - Logic actions

private extension LogViewer {
    func prepareShareItem(format: ExportFormat, fileName: String) -> ShareItem {
        guard let data = logr.exportLogs(format: format) else {
            return .empty
        }

        return ShareItem(data: data, fileName: fileName, contentType: format.contentType)
    }

    func clearAllLogs() {
        Task {
            do {
                try await logr.clearLogs()
            } catch {
                showError = error
            }
        }
    }

    func filterData() -> [LogEntry] {
        logr.recentLogs.filter { entry in
            guard selectedLevels.contains(entry.level) else { return false }

            if !selectedCategories.isEmpty, !selectedCategories.contains(entry.category) {
                return false
            }

            if !debouncedQuery.isEmpty {
                return entry.message.localizedCaseInsensitiveContains(debouncedQuery) ||
                    entry.category.rawValue.localizedCaseInsensitiveContains(debouncedQuery) ||
                    entry.category.displayName.localizedCaseInsensitiveContains(debouncedQuery)
            }

            return true
        }
    }
}

private struct NonAccessibleFeatureView: View {
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Missing Feature")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("AI Intelligence tool are only available on from iOS 26 and above.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    @Previewable @State var mock = MockLogR()
    LogViewer()
        .environment(\.logService, mock)
}

private extension ExportFormat {
    var exportFileName: String {
        "logs.\(fileExtension)"
    }
}
