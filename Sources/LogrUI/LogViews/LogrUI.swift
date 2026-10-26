//
//  LogrUI.swift
//  Logr
//
//  Created by martin on 01/11/2025.
//

import Combine
import Logr
import LogrNetwork
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
///     let logger = LogR(storage: .sqlite())
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
/// - Native AI features require iOS 26.0+ or macOS 26.0+ with an available model.
/// - The native file exporter is available on iOS and macOS.
///
/// ## Topics
///
/// ### Initializers
/// - ``init(functionalityFilter:)``
public struct LogViewer: View {
    @Environment(\.logService) private var logr
    @Environment(\.networkLogger) private var networkLogger
    @State private var logFilterPreferences = LogFilterPreferences()
    @State private var showingDeleteConfirmation = false
    @State private var presentedSheet: SheetDestination?
    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var showError: Error?
    private let functionalityFilter: Set<LogViewer.Functionalities>
    @State private var compactStatistics = LogStatisticsRefresher()

    enum SheetDestination: Identifiable {
        case filters
        case export
        case privacyLogChecks
        case issuesSummary
        case statistics
        case network

        var id: Self {
            self
        }
    }

    /// The optional parts of the viewer.
    public enum Functionalities: Equatable, CaseIterable {
        /// The "Analyze logs" menu, shown while the service can analyse logs.
        case analyser
        /// Export and sharing.
        case sharing
        /// The statistics sheet.
        case statistics
        /// A Network button, shown while the logs hold an entry `NetworkLogger` recorded, that opens
        /// ``NetworkLogView`` in a sheet.
        case network
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
    ///     let logger = LogR()
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
        mainContent
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
            #if os(iOS) || os(macOS)
            ExportSheet()
            #endif
        case .filters:
            FilterSheet()
                .environment(logFilterPreferences)
        case .privacyLogChecks:
            if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *) {
                NavigationStack {
                    PrivacyWarningsView()
                }
            } else {
                NonAccessibleFeatureView()
            }
        case .issuesSummary:
            if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *) {
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
        case .network:
            NetworkSheet()
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
                    CompactLogStatisticsView(statistics: compactStatistics.statistics)
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
        .navigationTitle("LogR Viewer")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .searchable(text: $searchText, prompt: "Search logs...")
        .task(id: compactStatisticsRefreshID) {
            await compactStatistics.refresh(from: logr,
                                            isActive: logFilterPreferences.showStatisticsPanel)
        }
        .task(id: searchText) {
            // Skip debounce for empty string (immediate clear)
            if searchText.isEmpty {
                debouncedQuery = ""
                return
            }
            // Debounce
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled {
                return
            }
            debouncedQuery = searchText
        }
        .toolbar {
            toolbarContent
        }
        .overlay {
            overlayContent(logs: logs)
        }
    }

    /// `nil` while the summary panel is hidden, so nothing schedules a refresh no one reads.
    var compactStatisticsRefreshID: LogEntries? {
        logFilterPreferences.showStatisticsPanel ? logr.recentLogs : nil
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
                    Text("Logs will appear here as your app records them.")
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
            if functionalityFilter.contains(.network),
               logr.recentLogs.contains(where: { NetworkRequest($0) != nil }) {
                Button {
                    presentedSheet = .network
                } label: {
                    Label("Network", systemImage: "network")
                }
            }

            Button("Filters") {
                presentedSheet = .filters
            }
            .disabled(logr.recentLogs.isEmpty)

            LogActionsMenu {
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
            LogActionsMenu {
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
        #if !os(tvOS)
        if !logr.recentLogs.isEmpty {
            LogActionsMenu("Export & Share") {
                ForEach(ExportFormat.allCases) { format in
                    ShareLink(item: ShareItem.logExport(from: logr, format: format),
                              preview: SharePreview("LogR Export")) {
                        Label("Share \(format.formatName)", systemImage: "square.and.arrow.up")
                    }
                }

                #if os(iOS) || os(macOS)
                Divider()

                Button {
                    presentedSheet = .export
                } label: {
                    Label("Export to Files", systemImage: "folder.fill")
                }
                #endif
            }
            Divider()
        }
        #endif
    }
}

// MARK: - Logic actions

private extension LogViewer {
    func clearAllLogs() {
        Task {
            // Bodies go even when the entries cannot be cleared: they are what holds request content.
            var failure: (any Error)?
            do {
                try await networkLogger?.clearBodies()
            } catch {
                failure = error
            }
            do {
                try await logr.clearLogs()
            } catch {
                failure = failure ?? error
            }
            showError = failure
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

private struct NetworkSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            NetworkLogView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
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
