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

/// A comprehensive SwiftUI view for displaying, filtering, and analyzing logs.
///
/// `LogViewer` provides a full-featured log viewing interface with:
/// - Real-time log display with automatic updates
/// - Advanced filtering by level, category, and search text
/// - Export and sharing in multiple formats (JSON, CSV, TXT)
/// - AI-powered privacy scanning and issue summarization (iOS 26+)
/// - Expandable/collapsible log entries
/// - Clear all logs functionality
///
/// ## Overview
///
/// The log viewer automatically connects to the LogR service through the SwiftUI
/// environment and displays logs in real-time as they're created.
///
/// ## Basic Usage
///
/// ```swift
/// import SwiftUI
/// import LogrUI
///
/// struct ContentView: View {
///     var body: some View {
///         NavigationStack {
///             LogViewer()
///         }
///     }
/// }
/// ```
///
/// ## Features
///
/// **Filtering**
/// - Filter by log levels (debug, info, notice, warning, error, fault)
/// - Filter by categories (network, ui, database, etc.)
/// - Full-text search across messages and categories
///
/// **Actions**
/// - Expand/collapse all log entries
/// - Export logs in JSON, CSV, or plain text format
/// - Share logs via system share sheet
/// - Clear all logs with confirmation
///
/// **AI Analysis** (iOS 26+)
/// - Scan for privacy issues and PII exposure
/// - Summarize critical issues and patterns
///
/// ## Complete Example
///
/// ```swift
/// import SwiftUI
/// import Logr
/// import LogrUI
///
/// @main
/// struct MyApp: App {
///     // Stored-property initializers can't use `try`; in real code prefer a throwing `init()`.
///     let logger = try! LogR(storage: SQLiteStorage())
///
///     var body: some Scene {
///         WindowGroup {
///             TabView {
///                 ContentView()
///                     .tabItem { Label("Home", systemImage: "house") }
///
///                 NavigationStack {
///                     LogViewer()
///                 }
///                 .tabItem { Label("Logs", systemImage: "list.bullet") }
///             }
///             .environment(\.logService, logger)
///         }
///     }
/// }
/// ```
///
/// ## Requirements
///
/// - iOS 17.0+, macOS 14.0+, tvOS 17.0+, watchOS 10.0+
/// - AI features require iOS 26.0+, macOS 26.0+, tvOS 26.0+, watchOS 12.0+
///
/// ## Topics
///
/// ### Initializers
/// - ``init()``
public struct LogViewer: View {
    @Environment(\.logService) private var logr
    @State private var logFilterPreferences = LogFilterPreferences()
    @State private var showingDeleteConfirmation = false
    @State private var shareItem: ShareItem?
    @State private var presentedSheet: SheetDestination?
    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var showError: Error?
    @State private var functionalityFilter = Set(LogViewer.Functionalities.allCases)
    @State private var compactStatistics: LogStatistics = .empty
    /// Share payloads precomputed off the main actor (export serialization is now `async`), so the
    /// `ShareLink`s — which need their item at view-build time — read a ready value.
    @State private var shareItems: [ExportFormat: ShareItem] = [:]

    enum SheetDestination: Identifiable {
        case filters
        case export
        case privacyLogChecks
        case issuesSummary
        case statistics

        var id: Self { self }
    }

    public enum Functionalities: Equatable, CaseIterable {
        case analyser
        case sharing
        case statistics
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
                "Failed to clear logs. Please try again later."
            }
        }
    }

    /// Creates a new log viewer instance.
    ///
    /// The log viewer automatically connects to the LogR service from the SwiftUI environment.
    /// Ensure you've configured a LogR instance using `.logRService(_:)` modifier higher
    /// in your view hierarchy.
    ///
    /// ## Example
    ///
    /// ```swift
    /// import SwiftUI
    /// import Logr
    /// import LogrUI
    ///
    /// @main
    /// struct MyApp: App {
    ///     // Stored-property initializers can't use `try`; in real code prefer a throwing `init()`.
    ///     let logger = try! LogR()
    ///
    ///     var body: some Scene {
    ///         WindowGroup {
    ///             NavigationStack {
    ///                 LogViewer()
    ///             }
    ///             .environment(\.logService, logger)
    ///         }
    ///     }
    /// }
    /// ```
    public init(functionalityFilter: [LogViewer.Functionalities] = LogViewer.Functionalities.allCases) {
        self.functionalityFilter = Set(functionalityFilter)
    }

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
            FilterSheet()
                .environment(logFilterPreferences)
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
        case .statistics:
            NavigationStack {
                LogStatisticsView()
            }
        }
    }

}

// MARK: - Main Content View

private extension LogViewer {
    var mainContent: some View {
        // Filter once per body pass and reuse everywhere below. Reading it repeatedly would
        // re-run the O(n) filter several times per update — costly on a large buffer.
        let logs = filterData()
        return List {
            // Statistics panel (collapsible)
            if logFilterPreferences.showStatisticsPanel, !logs.isEmpty {
                Section {
                    CompactLogStatisticsView(statistics: compactStatistics)
                }
            }

            // Log entries with optional grouping
            if logFilterPreferences.timeGrouping == .none {
                ForEach(logs) { entry in
                    logEntryRow(entry)
                }
            } else {
                ForEach(logs.grouped(by: logFilterPreferences.timeGrouping)) { group in
                    Section {
                        ForEach(group.logs) { entry in
                            logEntryRow(entry)
                        }
                    } header: {
                        HStack {
                            Text(group.title)
                            Spacer()
                            Text("\(group.logs.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search logs...")
        .task(id: logr.recentLogs.count) {
            // Recompute derived data (stats + share payloads) off the main actor when the cache
            // size changes, rather than synchronously on every body pass.
            await refreshDerivedData()
        }
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
            overlayContent(logs: logs)
        }
    }

    private func logEntryRow(_ entry: LogEntry) -> some View {
        #if os(macOS)
        LogEntryRow(entry: entry, displayState: $logFilterPreferences.allExpanded)
        #else
        LogEntryRow(entry: entry, displayState: $logFilterPreferences.allExpanded)
            .equatable()
        #endif
    }
}

// MARK: - Overlay

private extension LogViewer {
    @ViewBuilder
    func overlayContent(logs: [LogEntry]) -> some View {
        if logs.isEmpty, !searchText.isEmpty {
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
        } else if logs.isEmpty, debouncedQuery.isEmpty {
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
                Button(logFilterPreferences.allExpanded ? "Collapse All" : "Expand All") {
                    logFilterPreferences.allExpanded.toggle()
                }
                .disabled(logr.recentLogs.isEmpty)

                if functionalityFilter.contains(.statistics) {
                    Button("Logs statistics") {
                        presentedSheet = .statistics
                    }
                    .disabled(logr.recentLogs.isEmpty)
                }

                Divider()
                if functionalityFilter.contains(.analyser) {
                    logAnalyzeMenu
                }

                if functionalityFilter.contains(.sharing) {
                    shareMenu
                }

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
                    ShareLink(item: shareItems[format] ?? .empty,
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
    /// Refreshes the off-main–computed derived data: the compact statistics and, when sharing is
    /// enabled, the per-format share payloads. Serialization no longer runs on the main actor.
    func refreshDerivedData() async {
        compactStatistics = await logr.logStatistics()

        guard functionalityFilter.contains(.sharing), !logr.recentLogs.isEmpty else {
            shareItems = [:]
            return
        }
        var items: [ExportFormat: ShareItem] = [:]
        for format in ExportFormat.allCases {
            guard let data = try? await logr.exportLogs(format: format), !data.isEmpty else { continue }
            items[format] = ShareItem(data: data, fileName: format.formatName, contentType: format.contentType)
        }
        shareItems = items
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
        let debouncedQuery = debouncedQuery.lowercased()
       return logr.recentLogs.filter { entry in
            guard logFilterPreferences.selectedLevels.contains(entry.level) else { return false }

            if !logFilterPreferences.selectedCategories.isEmpty,
               !logFilterPreferences.selectedCategories.contains(entry.category) {
                return false
            }

            if !debouncedQuery.isEmpty {
                return entry.message.localizedCaseInsensitiveContains(debouncedQuery) ||
                    entry.category.rawValue.localizedCaseInsensitiveContains(debouncedQuery)
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

