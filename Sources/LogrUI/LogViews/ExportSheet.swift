//  
//  ExportSheet.swift
//  Logr
//
//  Created by Martin Lukacs on 17/11/2025.
//

import Logr
import SwiftUI

struct ExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.logService) var logr
    @State private var selectedFormat: ExportFormat = .json

    var body: some View {
        NavigationStack {
            List {
                exportFromatSection
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
    }

    //TODO: export in model or service
    private func exportLogs(format: ExportFormat) {
        Task {
            do {
                let data = try await logr.exportLogs(format: format)
                let fileName = "logs_\(Date().timeIntervalSince1970).\(format.fileExtension)"

                // Save to app's Documents directory
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let fileURL = documentsPath.appendingPathComponent(fileName)
                try data.write(to: fileURL)

                print("Logs exported to: \(fileURL.path)")
            } catch {
                print("Export failed: \(error)")
            }
        }
    }

    private func formatName(_ format: ExportFormat) -> String {
        switch format {
        case .json: "JSON"
        case .csv: "CSV"
        case .txt: "Plain Text"
        }
    }

    private func formatDescription(_ format: ExportFormat) -> String {
        switch format {
        case .json: "Structured data format, preserves all fields"
        case .csv: "Spreadsheet compatible, good for analysis"
        case .txt: "Human readable format, easy to view"
        }
    }
}

// MARK: - Sections
private extension ExportSheet {
    var exportFromatSection: some View {
        Section("Export Format") {
            ForEach([ExportFormat.json, .csv, .txt], id: \.self) { format in
                Button {
                    selectedFormat = format
                } label: {
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
                }
                .buttonStyle(.plain)
            }
        }
    }

    var exportingActionsSection: some View {
        Section {
            Button("Export to Files App") {
                exportLogs(format: selectedFormat)
                dismiss()
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

}
