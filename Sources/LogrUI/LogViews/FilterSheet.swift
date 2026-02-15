//
//  FilterSheet.swift
//  Logr
//
//  Created by Martin Lukacs on 16/11/2025.
//

import Logr
import SwiftUI

struct FilterSheet: View {
    @Environment(\.logService) private var logr
    @Environment(LogFilterPreferences.self) private var logFilterPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var availableCategories: [LogCategory] = []


    var body: some View {
        NavigationStack {
            List {
                logLevelsSection

                if !availableCategories.isEmpty {
                    categoriesSection
                }

                timeGroupingSection

                Toggle("Show logs summary", isOn: Bindable(logFilterPreferences).showStatisticsPanel)
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
        .task {
            setCategories()
        }
        .onChange(of: logr.recentLogs) {
            setCategories()
        }
    }

    func setCategories() {
        availableCategories = Array(Set(logr.recentLogs.map(\.category)))
    }
}

// MARK: - Sections

private extension FilterSheet {
    var logLevelsSection: some View {
        Section("Log Levels") {
            ForEach(LogLevel.allCases) { level in
                Button {
                    toggleLevel(level)
                } label: {
                    HStack {
                        LogLevelBadge(level: level)
                        Spacer()
                        if logFilterPreferences.selectedLevels.contains(level) {
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
                    logFilterPreferences.saveSelectedCategories(Set(availableCategories))
                }

                Spacer()

                Button("Clear All") {
                    logFilterPreferences.saveSelectedCategories([])
                }
            }
            .buttonStyle(.borderless)

            ForEach(availableCategories.sorted(by: { $0.displayName < $1.displayName })) { category in
                Button {
                    toggleCategory(category)
                } label: {
                    HStack {
                        Text(category.displayName)
                        Spacer()

                        if logFilterPreferences.selectedCategories.contains(category) {
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

    var timeGroupingSection: some View {
        Section("Time Grouping") {
            ForEach(LogTimeGrouping.allCases) { grouping in
                Button {
                    logFilterPreferences.saveTimeGrouping(grouping)
                } label: {
                    HStack {
                        Text(grouping.displayName)
                        Spacer()
                        if logFilterPreferences.timeGrouping == grouping {
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

// MARK: - Functions

private extension FilterSheet {
    func toggleCategory(_ category: LogCategory) {
        var currentCategories = logFilterPreferences.selectedCategories
        if currentCategories.contains(category) {
            currentCategories.remove(category)
        } else {
            currentCategories.insert(category)
        }
        logFilterPreferences.saveSelectedCategories(currentCategories)
    }

    func toggleLevel(_ level: LogLevel) {
        var currentLevels = logFilterPreferences.selectedLevels
        if currentLevels.contains(level) {
            currentLevels.remove(level)
        } else {
            currentLevels.insert(level)
        }

        logFilterPreferences.saveSelectedLevels(currentLevels)
    }
}
