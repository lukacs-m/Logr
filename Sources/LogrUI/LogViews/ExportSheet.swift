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

    // TODO: export in model or service
    private func exportLogs(format: ExportFormat) {
        do {
            guard let data = logr.exportLogs(format: format) else {
                return
            }
            let fileName = "logs_\(Date().timeIntervalSince1970).\(format.fileExtension)"

            // Save to app's Documents directory
            guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            else {
                return
            }
            let fileURL = documentsPath.appendingPathComponent(fileName)
            try data.write(to: fileURL)
        } catch {
            print("Export failed: \(error)")
        }
    }
}

// MARK: - Sections

private extension ExportSheet {
    var exportFromatSection: some View {
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
