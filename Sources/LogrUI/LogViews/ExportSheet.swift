//
//  ExportSheet.swift
//  Logr
//
//  Created by Martin Lukacs on 17/11/2025.
//

import Logr
import SwiftUI

#if os(iOS) || os(macOS)
struct ExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.logService) var logr
    @State private var selectedFormat: ExportFormat = .json
    @State private var exportItem: ShareItem?
    @State private var isPreparing = false
    @State private var showingExporter = false
    @State private var exportError: Error?

    var body: some View {
        NavigationStack {
            List {
                exportFormatSection
                exportingActionsSection
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
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 350)
        #endif
        .fileExporter(isPresented: $showingExporter,
                      item: exportItem,
                      contentTypes: [selectedFormat.contentType],
                      defaultFilename: exportItem?.fileName) { result in
            switch result {
            case .success:
                dismiss()
            case let .failure(error):
                exportError = error
            }
        }
        .alert("Export Failed", isPresented: Binding(get: { exportError != nil },
                                                     set: {
                                                         if !$0 {
                                                             exportError = nil
                                                         }
                                                     })) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError?.localizedDescription ?? "Please try again.")
        }
    }

    private func exportLogs(format: ExportFormat) async {
        isPreparing = true
        defer { isPreparing = false }
        do {
            let data = try await logr.exportLogs(format: format)
            guard !data.isEmpty else { return }
            exportItem = ShareItem(data: data, fileName: "logs.\(format.fileExtension)",
                                   contentType: format.contentType)
            showingExporter = true
        } catch {
            exportError = error
        }
    }
}

// MARK: - Sections

private extension ExportSheet {
    var exportFormatSection: some View {
        Section("Export Format") {
            ForEach(ExportFormat.allCases) { format in
                Button {
                    selectedFormat = format
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(format.formatName)
                                .fontWeight(.medium)
                            Text(format.formatDescription)
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
                }
                .buttonStyle(.plain)
                .disabled(isPreparing || showingExporter)
            }
        }
    }

    var exportingActionsSection: some View {
        Section {
            Button(isPreparing ? "Preparing Export…" : "Export to Files") {
                Task {
                    await exportLogs(format: selectedFormat)
                }
            }
            .disabled(isPreparing || showingExporter || logr.recentLogs.isEmpty)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
#endif
