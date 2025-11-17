//  
//  FilterSheet.swift
//  Logr
//
//  Created by Martin Lukacs on 16/11/2025.
//

import SwiftUI
import Logr

struct FilterSheet: View {
    @Environment(\.logService) private var logr
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedLevels: Set<LogLevel>
    @Binding var selectedCategories: Set<LogCategory>

    private var availableCategories: [LogCategory] {
         Array(Set(logr.recentLogs.map(\.category)))
     }

    var body: some View {
        NavigationStack {
            List {
                logLevelsSection

                if !availableCategories.isEmpty {
                    categoriesSection
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

// MARK: - Sections

private extension FilterSheet {
    var logLevelsSection: some View {
        Section("Log Levels") {
            ForEach(LogLevel.allCases) { level in
                Button {
                    if selectedLevels.contains(level) {
                        selectedLevels.remove(level)
                    } else {
                        selectedLevels.insert(level)
                    }
                } label: {
                    HStack {
                        LogLevelBadge(level: level)
                        Spacer()
                        if selectedLevels.contains(level) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    var categoriesSection: some View {
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

            ForEach(availableCategories.sorted(by: { $0.displayName < $1.displayName })) { category in
                Button {
                    if selectedCategories.contains(category) {
                        selectedCategories.remove(category)
                    } else {
                        selectedCategories.insert(category)
                    }
                } label: {
                    HStack {
                        Text(category.displayName)
                        Spacer()

                        if selectedCategories.contains(category) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
