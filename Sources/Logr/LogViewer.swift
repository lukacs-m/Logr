import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct LogViewer: View {
    @State private var logr: LogR
    @State private var searchText = ""
    @State private var selectedLevels: Set<LogLevel> = Set(LogLevel.allCases)
    @State private var selectedCategories: Set<String> = []
    @State private var availableCategories: Set<String> = []
    @State private var showingFilters = false
    @State private var showingExport = false
    @State private var showingDeleteConfirmation = false
    @State private var selectedExportFormat: ExportFormat = .json
    @State private var exportedData: Data?
    
    public init(logr: LogR = .shared) {
        self._logr = State(initialValue: logr)
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if logr.isCleanupRunning {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Cleaning up logs...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.secondary.opacity(0.1))
                }
                
                List {
                    ForEach(filteredLogs, id: \.id) { entry in
                        LogEntryRow(entry: entry)
                    }
                }
                .searchable(text: $searchText, prompt: "Search logs...")
                .refreshable {
                    await refreshLogs()
                }
            }
            .navigationTitle("LogR Viewer")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Filters") {
                        showingFilters = true
                    }
                    .disabled(logr.recentLogs.isEmpty)
                    
                    Button("Export") {
                        showingExport = true
                    }
                    .disabled(filteredLogs.isEmpty)
                    
                    Button("Clear") {
                        showingDeleteConfirmation = true
                    }
                    .disabled(logr.recentLogs.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showingFilters) {
            FilterSheet(
                selectedLevels: $selectedLevels,
                selectedCategories: $selectedCategories,
                availableCategories: Array(availableCategories)
            )
        }
        .sheet(isPresented: $showingExport) {
            ExportSheet(
                selectedFormat: $selectedExportFormat,
                onExport: exportLogs
            )
        }
        .confirmationDialog(
            "Clear All Logs",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All Logs", role: .destructive) {
                Task {
                    try? await logr.clearLogs()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete all stored log entries. This action cannot be undone.")
        }
        .onAppear {
            updateAvailableCategories()
        }
        .onChange(of: logr.recentLogs) { _, _ in
            updateAvailableCategories()
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
                $0.category.localizedCaseInsensitiveContains(searchText) ||
                $0.subsystem.localizedCaseInsensitiveContains(searchText)
            }
        
        return searchFiltered
    }
    
    private func updateAvailableCategories() {
        availableCategories = Set(logr.recentLogs.map(\.category))
    }
    
    private func refreshLogs() async {
        // The @Observable LogR will automatically update recentLogs
    }
    
    private func exportLogs() {
        Task {
            do {
                let data = try await logr.exportLogs(format: selectedExportFormat)
                await MainActor.run {
                    exportedData = data
                }
            } catch {
                print("Export failed: \(error)")
            }
        }
    }
}

struct LogEntryRow: View {
    let entry: LogEntry
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                LogLevelBadge(level: entry.level)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(entry.category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text(entry.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    
                    Text(entry.message)
                        .font(.body)
                        .lineLimit(isExpanded ? nil : 3)
                }
                
                Spacer()
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                    
                    Group {
                        DetailRow("Subsystem", entry.subsystem)
                        DetailRow("File", URL(fileURLWithPath: entry.file).lastPathComponent)
                        DetailRow("Function", entry.function)
                        DetailRow("Line", "\(entry.line)")
                        DetailRow("Timestamp", entry.timestamp.formatted(.iso8601))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
    
    var body: some View {
        HStack {
            Text("\(label):")
                .fontWeight(.medium)
            Text(value)
            Spacer()
        }
    }
}

struct LogLevelBadge: View {
    let level: LogLevel
    
    var body: some View {
        Text(level.displayName.uppercased())
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .clipShape(Capsule())
    }
    
    private var backgroundColor: Color {
        switch level {
        case .debug: return .gray
        case .info: return .blue
        case .notice: return .green
        case .error: return .orange
        case .fault: return .red
        }
    }
    
    private var foregroundColor: Color {
        .white
    }
}

struct FilterSheet: View {
    @Binding var selectedLevels: Set<LogLevel>
    @Binding var selectedCategories: Set<String>
    let availableCategories: [String]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("Log Levels") {
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        HStack {
                            LogLevelBadge(level: level)
                            Spacer()
                            
                            if selectedLevels.contains(level) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedLevels.contains(level) {
                                selectedLevels.remove(level)
                            } else {
                                selectedLevels.insert(level)
                            }
                        }
                    }
                }
                
                if !availableCategories.isEmpty {
                    Section("Categories") {
                        HStack {
                            Button("Select All") {
                                selectedCategories = Set(availableCategories)
                            }
                            
                            Spacer()
                            
                            Button("Clear All") {
                                selectedCategories.removeAll()
                            }
                        }
                        .buttonStyle(.borderless)
                        
                        ForEach(availableCategories.sorted(), id: \.self) { category in
                            HStack {
                                Text(category)
                                Spacer()
                                
                                if selectedCategories.contains(category) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedCategories.contains(category) {
                                    selectedCategories.remove(category)
                                } else {
                                    selectedCategories.insert(category)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ExportSheet: View {
    @Binding var selectedFormat: ExportFormat
    let onExport: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("Export Format") {
                    ForEach([ExportFormat.json, .csv, .txt], id: \.self) { format in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(formatName(format))
                                    .fontWeight(.medium)
                                Text(formatDescription(format))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            if selectedFormat == format {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundColor(.gray)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedFormat = format
                        }
                    }
                }
                
                Section {
                    Button("Export Logs") {
                        onExport()
                        dismiss()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("Export Logs")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func formatName(_ format: ExportFormat) -> String {
        switch format {
        case .json: return "JSON"
        case .csv: return "CSV"
        case .txt: return "Plain Text"
        }
    }
    
    private func formatDescription(_ format: ExportFormat) -> String {
        switch format {
        case .json: return "Structured data format, preserves all fields"
        case .csv: return "Spreadsheet compatible, good for analysis"
        case .txt: return "Human readable format, easy to view"
        }
    }
}

#Preview {
    LogViewer()
}