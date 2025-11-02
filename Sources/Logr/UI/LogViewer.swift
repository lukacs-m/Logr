//import SwiftUI
//import UniformTypeIdentifiers
//
//#if canImport(UIKit)
//import UIKit
//#elseif canImport(AppKit)
//import AppKit
//#endif
//
//// MARK: - Share Item
//
//public struct ShareItem: Transferable {
//    let data: Data
//    let fileName: String
//    let contentType: UTType
//    
//    public static var transferRepresentation: some TransferRepresentation {
//        DataRepresentation(contentType: .data) { item in
//            item.data
//        } importing: { data in
//            ShareItem(data: data, fileName: "imported.json", contentType: .json)
//        }
//        .suggestedFileName { item in
//            item.fileName
//        }
//    }
//}
//
//public struct LogViewer: View {
//    @Environment(LogRService) private var logr
//    @State private var searchText = ""
//    @State private var selectedLevels: Set<LogLevel> = Set(LogLevel.allCases)
//    @State private var selectedCategories: Set<LogCategory> = []
//    @State private var availableCategories: Set<LogCategory> = []
//    @State private var showingFilters = false
//    @State private var showingExport = false
//    @State private var showingDeleteConfirmation = false
//    @State private var selectedExportFormat: ExportFormat = .json
//    @State private var shareItem: ShareItem?
//    
//    public init() {}
//    
//    @available(*, deprecated, message: "Use init() and provide LogRService via environment")
//    public init(logr: LogRService) {
//        // This initializer is kept for backward compatibility but deprecated
//        // Users should use the environment-based approach
//    }
//    
//    public var body: some View {
//        NavigationStack {
//            VStack(spacing: 0) {
//                if logr.isCleanupRunning {
//                    HStack {
//                        ProgressView()
//                            .scaleEffect(0.8)
//                        Text("Cleaning up logs...")
//                            .font(.caption)
//                            .foregroundStyle(.secondary)
//                    }
//                    .padding(.vertical, 8)
//                    .frame(maxWidth: .infinity)
//                    .background(Color.secondary.opacity(0.1))
//                }
//                
//                List {
//                    ForEach(filteredLogs, id: \.id) { entry in
//                        LogEntryRow(entry: entry)
//                    }
//                }
//                .searchable(text: $searchText, prompt: "Search logs...")
//                .refreshable {
//                    await refreshLogs()
//                }
//            }
//            .navigationTitle("LogR Viewer")
//            .toolbar {
//                ToolbarItemGroup(placement: .primaryAction) {
//                    Button("Filters") {
//                        showingFilters = true
//                    }
//                    .disabled(logr.recentLogs.isEmpty)
//                    
//                    Menu {
//                        Menu("Share") {
//                            ShareLink(
//                                item: shareItem ?? ShareItem(
//                                    data: Data(),
//                                    fileName: "logs.json",
//                                    contentType: .json
//                                ),
//                                preview: SharePreview("LogR Export")
//                            ) {
//                                Label("Share as JSON", systemImage: "square.and.arrow.up")
//                            }
//                            .disabled(filteredLogs.isEmpty)
//                            .task {
//                                if shareItem == nil {
//                                    await prepareShareItem(format: .json)
//                                }
//                            }
//                            
//                            Button("Share as CSV") {
//                                Task { await prepareShareItem(format: .csv) }
//                            }
//                            .disabled(filteredLogs.isEmpty)
//                            
//                            Button("Share as Text") {
//                                Task { await prepareShareItem(format: .txt) }
//                            }
//                            .disabled(filteredLogs.isEmpty)
//                        }
//                        
//                        Button("Export to Files") {
//                            showingExport = true
//                        }
//                        .disabled(filteredLogs.isEmpty)
//                        
//                        Divider()
//                        
//                        Button("Clear All Logs", role: .destructive) {
//                            showingDeleteConfirmation = true
//                        }
//                        .disabled(logr.recentLogs.isEmpty)
//                        
//                    } label: {
//                        Image(systemName: "ellipsis.circle")
//                    }
//                    .disabled(logr.recentLogs.isEmpty)
//                }
//            }
//        }
//        .sheet(isPresented: $showingFilters) {
//            FilterSheet(
//                selectedLevels: $selectedLevels,
//                selectedCategories: $selectedCategories,
//                availableCategories: Array(availableCategories)
//            )
//        }
//        .sheet(isPresented: $showingExport) {
//            ExportSheet(
//                selectedFormat: $selectedExportFormat,
//                onExport: { exportLogs(format: selectedExportFormat) }
//            )
//        }
//        .confirmationDialog(
//            "Clear All Logs",
//            isPresented: $showingDeleteConfirmation,
//            titleVisibility: .visible
//        ) {
//            Button("Clear All Logs", role: .destructive) {
//                Task {
//                    try? await logr.clearLogs()
//                }
//            }
//            Button("Cancel", role: .cancel) { }
//        } message: {
//            Text("This will permanently delete all stored log entries. This action cannot be undone.")
//        }
//        .onAppear {
//            updateAvailableCategories()
//        }
//        .onChange(of: logr.recentLogs) { _, _ in
//            updateAvailableCategories()
//        }
//    }
//    
//    private var filteredLogs: [LogEntry] {
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
//                $0.category.rawValue.localizedCaseInsensitiveContains(searchText) ||
//                $0.category.displayName.localizedCaseInsensitiveContains(searchText) ||
//                $0.subsystem.localizedCaseInsensitiveContains(searchText)
//            }
//        
//        return searchFiltered
//    }
//    
//    private func updateAvailableCategories() {
//        availableCategories = Set(logr.recentLogs.map(\.category))
//    }
//    
//    private func refreshLogs() async {
//        // The @Observable LogR will automatically update recentLogs
//    }
//    
//    private func prepareShareItem(format: ExportFormat) async {
//        do {
//            let data = try await logr.exportLogs(format: format)
//            let fileName = "logs_\(Date().timeIntervalSince1970).\(format.fileExtension)"
//            let contentType: UTType = switch format {
//            case .json: .json
//            case .csv: .commaSeparatedText
//            case .txt: .plainText
//            }
//            
//            shareItem = ShareItem(data: data, fileName: fileName, contentType: contentType)
//        } catch {
//            print("Failed to prepare share item: \(error)")
//        }
//    }
//    
//    private func exportLogs(format: ExportFormat) {
//        Task {
//            do {
//                let data = try await logr.exportLogs(format: format)
//                let fileName = "logs_\(Date().timeIntervalSince1970).\(format.fileExtension)"
//                
//                // Save to app's Documents directory
//                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
//                let fileURL = documentsPath.appendingPathComponent(fileName)
//                try data.write(to: fileURL)
//                
//                print("Logs exported to: \(fileURL.path)")
//            } catch {
//                print("Export failed: \(error)")
//            }
//        }
//    }
//}
//
//struct LogEntryRow: View {
//    let entry: LogEntry
//    @State private var isExpanded = false
//    
//    var body: some View {
//        VStack(alignment: .leading, spacing: 4) {
//            HStack {
//                LogLevelBadge(level: entry.level)
//                
//                VStack(alignment: .leading, spacing: 2) {
//                    HStack {
//                        Text(entry.category.displayName)
//                            .font(.caption)
//                            .foregroundStyle(.secondary)
//                        
//                        Spacer()
//                        
//                        Text(entry.timestamp, style: .time)
//                            .font(.caption2)
//                            .foregroundStyle(.tertiary)
//                    }
//                    
//                    Text(entry.message)
//                        .font(.body)
//                        .lineLimit(isExpanded ? nil : 3)
//                }
//                
//                Spacer()
//            }
//            
//            if isExpanded {
//                VStack(alignment: .leading, spacing: 4) {
//                    Divider()
//                    
//                    Group {
//                        DetailRow("Subsystem", entry.subsystem)
//                        DetailRow("File", URL(fileURLWithPath: entry.file).lastPathComponent)
//                        DetailRow("Function", entry.function)
//                        DetailRow("Line", "\(entry.line)")
//                        DetailRow("Timestamp", entry.timestamp.formatted(.iso8601))
//                    }
//                    .font(.caption)
//                    .foregroundStyle(.secondary)
//                }
//            }
//        }
//        .contentShape(Rectangle())
//        .onTapGesture {
//            withAnimation(.easeInOut(duration: 0.2)) {
//                isExpanded.toggle()
//            }
//        }
//    }
//}
//
//struct DetailRow: View {
//    let label: String
//    let value: String
//    
//    init(_ label: String, _ value: String) {
//        self.label = label
//        self.value = value
//    }
//    
//    var body: some View {
//        HStack {
//            Text("\(label):")
//                .fontWeight(.medium)
//            Text(value)
//            Spacer()
//        }
//    }
//}
//
//struct LogLevelBadge: View {
//    let level: LogLevel
//    
//    var body: some View {
//        Text(level.displayName.uppercased())
//            .font(.caption2)
//            .fontWeight(.semibold)
//            .padding(.horizontal, 8)
//            .padding(.vertical, 2)
//            .background(backgroundColor)
//            .foregroundColor(foregroundColor)
//            .clipShape(Capsule())
//    }
//    
//    private var backgroundColor: Color {
//        switch level {
//        case .debug: return .gray
//        case .info: return .blue
//        case .notice: return .green
//        case .error: return .orange
//        case .fault: return .red
//        }
//    }
//    
//    private var foregroundColor: Color {
//        .white
//    }
//}
//
//struct FilterSheet: View {
//    @Binding var selectedLevels: Set<LogLevel>
//    @Binding var selectedCategories: Set<LogCategory>
//    let availableCategories: [LogCategory]
//    @Environment(\.dismiss) private var dismiss
//    
//    var body: some View {
//        NavigationStack {
//            List {
//                Section("Log Levels") {
//                    ForEach(LogLevel.allCases, id: \.self) { level in
//                        HStack {
//                            LogLevelBadge(level: level)
//                            Spacer()
//                            
//                            if selectedLevels.contains(level) {
//                                Image(systemName: "checkmark")
//                                    .foregroundColor(.blue)
//                            }
//                        }
//                        .contentShape(Rectangle())
//                        .onTapGesture {
//                            if selectedLevels.contains(level) {
//                                selectedLevels.remove(level)
//                            } else {
//                                selectedLevels.insert(level)
//                            }
//                        }
//                    }
//                }
//                
//                if !availableCategories.isEmpty {
//                    Section("Categories") {
//                        HStack {
//                            Button("Select All") {
//                                selectedCategories = Set(availableCategories)
//                            }
//                            
//                            Spacer()
//                            
//                            Button("Clear All") {
//                                selectedCategories.removeAll()
//                            }
//                        }
//                        .buttonStyle(.borderless)
//                        
//                        ForEach(availableCategories.sorted(by: { $0.displayName < $1.displayName }), id: \.self) { category in
//                            HStack {
//                                Text(category.displayName)
//                                Spacer()
//                                
//                                if selectedCategories.contains(category) {
//                                    Image(systemName: "checkmark")
//                                        .foregroundColor(.blue)
//                                }
//                            }
//                            .contentShape(Rectangle())
//                            .onTapGesture {
//                                if selectedCategories.contains(category) {
//                                    selectedCategories.remove(category)
//                                } else {
//                                    selectedCategories.insert(category)
//                                }
//                            }
//                        }
//                    }
//                }
//            }
//            .navigationTitle("Filters")
//            .toolbar {
//                ToolbarItem(placement: .confirmationAction) {
//                    Button("Done") {
//                        dismiss()
//                    }
//                }
//            }
//        }
//    }
//}
//
//struct ExportSheet: View {
//    @Binding var selectedFormat: ExportFormat
//    let onExport: () -> Void
//    @Environment(\.dismiss) private var dismiss
//    
//    var body: some View {
//        NavigationStack {
//            List {
//                Section("Export Format") {
//                    ForEach([ExportFormat.json, .csv, .txt], id: \.self) { format in
//                        HStack {
//                            VStack(alignment: .leading) {
//                                Text(formatName(format))
//                                    .fontWeight(.medium)
//                                Text(formatDescription(format))
//                                    .font(.caption)
//                                    .foregroundStyle(.secondary)
//                            }
//                            
//                            Spacer()
//                            
//                            if selectedFormat == format {
//                                Image(systemName: "checkmark.circle.fill")
//                                    .foregroundColor(.blue)
//                            } else {
//                                Image(systemName: "circle")
//                                    .foregroundColor(.gray)
//                            }
//                        }
//                        .contentShape(Rectangle())
//                        .onTapGesture {
//                            selectedFormat = format
//                        }
//                    }
//                }
//                
//                Section {
//                    Button("Export to Files App") {
//                        onExport()
//                        dismiss()
//                    }
//                    .frame(maxWidth: .infinity, alignment: .center)
//                }
//            }
//            .navigationTitle("Export Logs")
//            .toolbar {
//                ToolbarItem(placement: .cancellationAction) {
//                    Button("Cancel") {
//                        dismiss()
//                    }
//                }
//            }
//        }
//    }
//    
//    private func formatName(_ format: ExportFormat) -> String {
//        switch format {
//        case .json: return "JSON"
//        case .csv: return "CSV"
//        case .txt: return "Plain Text"
//        }
//    }
//    
//    private func formatDescription(_ format: ExportFormat) -> String {
//        switch format {
//        case .json: return "Structured data format, preserves all fields"
//        case .csv: return "Spreadsheet compatible, good for analysis"
//        case .txt: return "Human readable format, easy to view"
//        }
//    }
//}
//
//#Preview {
//    @Previewable @State var mock = MockLogR()
//    LogViewer()
//        .environment(mock)
//}
