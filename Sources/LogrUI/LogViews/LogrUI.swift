//
//  LogrUI.swift
//  Logr
//
//  Created by martin on 01/11/2025.
//

import Logr
import SwiftUI
import UniformTypeIdentifiers

////TODO: logic in model for search debounce + test with 1000 elements
//public struct LogViewer: View {
//    @Environment(\.logService) private var logr
//    @State private var searchText = ""
//    @State private var selectedLevels: Set<LogLevel> = Set(LogLevel.allCases)
//    @State private var selectedCategories: Set<LogCategory> = []
//    @State private var showingFilters = false
//    @State private var showingExport = false
//    @State private var showingDeleteConfirmation = false
//    @State private var shareItem: ShareItem?
//    @State private var allExpanded = false
//
//    public init() {}
//
//    public var body: some View {
//        NavigationStack {
//            List {
//                ForEach(filteredLogs) { entry in
//                    LogEntryRow(entry: entry, displayState: $allExpanded)
//                }
//            }
//            .searchable(text: $searchText, prompt: "Search logs...")
//            .navigationTitle("LogR Viewer")
//            .toolbar {
//                toolbarContent
//            }
//        }
//        .sheet(isPresented: $showingFilters) {
//            FilterSheet(selectedLevels: $selectedLevels,
//                        selectedCategories: $selectedCategories)
//        }
//        .sheet(isPresented: $showingExport) {
//            ExportSheet()
//        }
//        .confirmationDialog("Clear All Logs",
//                            isPresented: $showingDeleteConfirmation,
//                            titleVisibility: .visible) {
//            Button("Clear All Logs", role: .destructive) {
//                Task {
//                    try? await logr.clearLogs()
//                }
//            }
//            Button("Cancel", role: .cancel) {}
//        } message: {
//            Text("This will permanently delete all stored log entries. This action cannot be undone.")
//        }
//    }
//
//    private var filteredLogs: [LogEntry] {
//        
//        let levelFiltered = logr.recentLogs.filter { selectedLevels.contains($0.level) }
//
//        let categoryFiltered = selectedCategories.isEmpty
//            ? levelFiltered
//            : levelFiltered.filter { selectedCategories.contains($0.category) }
//
//        let searchFiltered = searchText.isEmpty
//            ? categoryFiltered
//            : categoryFiltered.filter {
//                $0.message.localizedCaseInsensitiveContains(searchText) ||
//                    $0.category.rawValue.localizedCaseInsensitiveContains(searchText) ||
//                    $0.category.displayName.localizedCaseInsensitiveContains(searchText)
//            }
//
//        return searchFiltered
//    }
//
//    private func prepareShareItem(format: ExportFormat) async {
//        do {
//            guard let data = try await logr.exportLogs(format: format) else {
//                return
//            }
//            let fileName = "logs_\(Date().timeIntervalSince1970).\(format.fileExtension)"
//  
//            shareItem = ShareItem(data: data, fileName: fileName, contentType: format.contentType)
//        } catch {
//            print("Failed to prepare share item: \(error)")
//        }
//    }
//}
//
//// MARK: - Toolbar actions
//private extension LogViewer {
//    var toolbarContent: some ToolbarContent {
//        ToolbarItemGroup(placement: .primaryAction) {
//            Button("Filters") {
//                showingFilters = true
//            }
//            .disabled(logr.recentLogs.isEmpty)
//
//            Menu {
//                Button(allExpanded ? "Collapse All" : "Expand All") {
//                    allExpanded.toggle()
//                }
//                .disabled(logr.recentLogs.isEmpty)
//
//                Menu("Share") {
//                    ShareLink(item: shareItem ?? ShareItem(data: Data(),
//                                                           fileName: "logs.json",
//                                                           contentType: .json),
//                              preview: SharePreview("LogR Export")) {
//                        Label("Share as JSON", systemImage: "square.and.arrow.up")
//                    }
//                    .disabled(filteredLogs.isEmpty)
//                    .task {
//                        if shareItem == nil {
//                            await prepareShareItem(format: .json)
//                        }
//                    }
//
//                    Button("Share as CSV") {
//                        Task { await prepareShareItem(format: .csv) }
//                    }
//                    .disabled(filteredLogs.isEmpty)
//
//                    Button("Share as Text") {
//                        Task { await prepareShareItem(format: .txt) }
//                    }
//                    .disabled(filteredLogs.isEmpty)
//                }
//
//                Button("Export to Files") {
//                    showingExport = true
//                }
//                .disabled(filteredLogs.isEmpty)
//
//                Divider()
//
//                Button("Clear All Logs", role: .destructive) {
//                    showingDeleteConfirmation = true
//                }
//                .disabled(logr.recentLogs.isEmpty)
//
//            } label: {
//                Image(systemName: "ellipsis.circle")
//            }
//            .disabled(logr.recentLogs.isEmpty)
//        }
//    }
//}
//
//@Observable
//final class LogViewerStateModel {
//    private var logService: (any LogRService)?
//    
//    init() {}
//    
//    func setUp(with logService: any LogRService) {
//        self.logService = logService
//    }
//}
//
//#Preview {
//    @Previewable @State var mock = MockLogR()
//    LogViewer()
//        .environment(\.logService, mock)
//}

//TODO: logic in model for search debounce + test with 1000 elements
public struct LogViewer: View {
    @Environment(\.logService) private var logr
    @State private var stateModel = LogViewerStateModel()
//    @State private var showingFilters = false
//    @State private var showingExport = false
    @State private var showingDeleteConfirmation = false
    @State private var shareItem: ShareItem?
    @State private var presentedSheet: SheetDestination?

    enum SheetDestination: Identifiable {
        case filters
        case export
        
        var id: Self { self }
    }

    public init() {
        stateModel.setUp(with: logr)
    }

    public var body: some View {
        NavigationStack {
            List {
                ForEach(filteredLogs) { entry in
                    LogEntryRow(entry: entry, displayState: $stateModel.allExpanded)
                }
            }
            .searchable(text: $stateModel.searchText, prompt: "Search logs...")
            .navigationTitle("LogR Viewer")
            .toolbar {
                toolbarContent
            }
        }
        .sheet(item: $presentedSheet) { destination in
            sheetView(destination: destination)
        }
        .confirmationDialog("Clear All Logs",
                            isPresented: $showingDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Clear All Logs", role: .destructive) {
                stateModel.clearAllLogs()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all stored log entries. This action cannot be undone.")
        }
    }

    private var filteredLogs: [LogEntry] {
        
        let levelFiltered = logr.recentLogs.filter { stateModel.selectedLevels.contains($0.level) }

        let categoryFiltered = stateModel.selectedCategories.isEmpty
            ? levelFiltered
        : levelFiltered.filter { stateModel.selectedCategories.contains($0.category) }

        let searchFiltered = stateModel.searchText.isEmpty
            ? categoryFiltered
            : categoryFiltered.filter {
                $0.message.localizedCaseInsensitiveContains(stateModel.searchText) ||
                $0.category.rawValue.localizedCaseInsensitiveContains(stateModel.searchText) ||
                $0.category.displayName.localizedCaseInsensitiveContains(stateModel.searchText)
            }

        return searchFiltered
    }

    private func prepareShareItem(format: ExportFormat) async {
        do {
            guard let data = try await logr.exportLogs(format: format) else {
                return
            }
            let fileName = "logs_\(Date().timeIntervalSince1970).\(format.fileExtension)"
  
            shareItem = ShareItem(data: data, fileName: fileName, contentType: format.contentType)
        } catch {
            print("Failed to prepare share item: \(error)")
        }
    }
    
    @ViewBuilder
    func sheetView(destination: SheetDestination) -> some View {
        switch destination {
        case .export:
            ExportSheet()
        case .filters:
            FilterSheet(selectedLevels: $stateModel.selectedLevels,
                        selectedCategories: $stateModel.selectedCategories)
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
                Button(stateModel.allExpanded ? "Collapse All" : "Expand All") {
                    stateModel.toggleAllExpanded()
                }
                .disabled(logr.recentLogs.isEmpty)
                
                Menu("Export & Share") {
                    // Format selection buttons
                    ForEach(ExportFormat.allCases) { format in
                        Button("Prepare \(format.fileExtension) export") {
                            Task { await prepareShareItem(format: format) }
                        }
                    }
                    
                    Divider()
                    
                    // ShareLink only visible when item is ready
                    if let item = shareItem {
                        ShareLink(item: item, preview: SharePreview("LogR Export")) {
                            Label("Share \(item.fileName)", systemImage: "square.and.arrow.up")
                        }
                    }
                    
                    ShareLink(item: shareItem ?? ShareItem(data: Data(), uti: "public.text"), preview: SharePreview("LogR Export")) {
                        
                    }
                }
                .disabled(filteredLogs.isEmpty)

//                Menu("Share") {
//                    Button("Share as JSON") {
//                        Task { await prepareShareItem(format: .json) }
//                    }
//                    .disabled(filteredLogs.isEmpty)
//                    
//                    Button("Share as CSV") {
//                        Task { await prepareShareItem(format: .csv) }
//                    }
//                    .disabled(filteredLogs.isEmpty)
//                    
//                    Button("Share as Text") {
//                        Task { await prepareShareItem(format: .txt) }
//                    }
//                    .disabled(filteredLogs.isEmpty)
//                }
             

//                Menu("Share") {
//                    ShareLink(item: shareItem ?? ShareItem(data: Data(),
//                                                           fileName: "logs.json",
//                                                           contentType: .json),
//                              preview: SharePreview("LogR Export")) {
//                        Label("Share as JSON", systemImage: "square.and.arrow.up")
//                    }
//                    .disabled(filteredLogs.isEmpty)
//                    .task {
//                        if shareItem == nil {
//                            await prepareShareItem(format: .json)
//                        }
//                    }
//
//                    Button("Share as CSV") {
//                        Task { await prepareShareItem(format: .csv) }
//                    }
//                    .disabled(filteredLogs.isEmpty)
//
//                    Button("Share as Text") {
//                        Task { await prepareShareItem(format: .txt) }
//                    }
//                    .disabled(filteredLogs.isEmpty)
//                }

                Button("Export to Files") {
                    presentedSheet = .export
                }
                .disabled(filteredLogs.isEmpty)

                Divider()

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
    func test() -> ShareItem {
        Data()
    }
}

@Observable
final class LogViewerStateModel {
    private var logService: (any LogRService)?
    var searchText = ""
    var selectedLevels: Set<LogLevel> = Set(LogLevel.allCases)
    var selectedCategories: Set<LogCategory> = []
    var shareItem: ShareItem?
    var allExpanded = false
    
    init() {}
    
    func setUp(with logService: any LogRService) {
        self.logService = logService
    }
    
    func clearAllLogs() {
        guard let logService else {
            return
        }
        Task {
            do {
                try await logService.clearLogs()
            } catch {
                print("Failed to clear logs: \(error)")
            }
        }
    }
    
    func toggleAllExpanded() {
        allExpanded.toggle()
    }
}

#Preview {
    @Previewable @State var mock = MockLogR()
    LogViewer()
        .environment(\.logService, mock)
}
