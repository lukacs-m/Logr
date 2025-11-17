//
//  LogrUI.swift
//  Logr
//
//  Created by martin on 01/11/2025.
//

import Logr
import SwiftUI
import UniformTypeIdentifiers

//TODO: logic in model for search debounce + test with 1000 elements
public struct LogViewer: View {
    @Environment(\.logService) private var logr
    @State private var searchText = ""
    @State private var selectedLevels: Set<LogLevel> = Set(LogLevel.allCases)
    @State private var selectedCategories: Set<LogCategory> = []
    @State private var showingFilters = false
    @State private var showingExport = false
    @State private var showingDeleteConfirmation = false
    @State private var shareItem: ShareItem?
    @State private var allExpanded = false

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                ForEach(filteredLogs) { entry in
                    LogEntryRow(entry: entry, displayState: $allExpanded)
                }
            }
            .searchable(text: $searchText, prompt: "Search logs...")
            .navigationTitle("LogR Viewer")
            .toolbar {
                toolbarContent
            }
        }
        .sheet(isPresented: $showingFilters) {
            FilterSheet(selectedLevels: $selectedLevels,
                        selectedCategories: $selectedCategories)
        }
        .sheet(isPresented: $showingExport) {
            ExportSheet()
        }
        .confirmationDialog("Clear All Logs",
                            isPresented: $showingDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Clear All Logs", role: .destructive) {
                Task {
                    try? await logr.clearLogs()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all stored log entries. This action cannot be undone.")
        }
    }

    private var filteredLogs: [LogEntry] {
        let levelFiltered = logr.recentLogs.filter { selectedLevels.contains($0.level) }

        let categoryFiltered = selectedCategories.isEmpty
            ? levelFiltered
            : levelFiltered.filter { selectedCategories.contains($0.category) }

        let searchFiltered = searchText.isEmpty
            ? categoryFiltered
            : categoryFiltered.filter {
                $0.message.localizedCaseInsensitiveContains(searchText) ||
                    $0.category.rawValue.localizedCaseInsensitiveContains(searchText) ||
                    $0.category.displayName.localizedCaseInsensitiveContains(searchText)
            }

        return searchFiltered
    }

    private func prepareShareItem(format: ExportFormat) async {
        do {
            let data = try await logr.exportLogs(format: format)
            let fileName = "logs_\(Date().timeIntervalSince1970).\(format.fileExtension)"
            let contentType: UTType = switch format {
            case .json: .json
            case .csv: .commaSeparatedText
            case .txt: .plainText
            }

            shareItem = ShareItem(data: data, fileName: fileName, contentType: contentType)
        } catch {
            print("Failed to prepare share item: \(error)")
        }
    }
}

// MARK: - Toolbar actions
private extension LogViewer {
    var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Filters") {
                showingFilters = true
            }
            .disabled(logr.recentLogs.isEmpty)

            Menu {
                Button(allExpanded ? "Collapse All" : "Expand All") {
                    allExpanded.toggle()
                }
                .disabled(logr.recentLogs.isEmpty)

                Menu("Share") {
                    ShareLink(item: shareItem ?? ShareItem(data: Data(),
                                                           fileName: "logs.json",
                                                           contentType: .json),
                              preview: SharePreview("LogR Export")) {
                        Label("Share as JSON", systemImage: "square.and.arrow.up")
                    }
                    .disabled(filteredLogs.isEmpty)
                    .task {
                        if shareItem == nil {
                            await prepareShareItem(format: .json)
                        }
                    }

                    Button("Share as CSV") {
                        Task { await prepareShareItem(format: .csv) }
                    }
                    .disabled(filteredLogs.isEmpty)

                    Button("Share as Text") {
                        Task { await prepareShareItem(format: .txt) }
                    }
                    .disabled(filteredLogs.isEmpty)
                }

                Button("Export to Files") {
                    showingExport = true
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
}

#Preview {
    @Previewable @State var mock = MockLogR()
    LogViewer()
        .environment(\.logService, mock)
}
