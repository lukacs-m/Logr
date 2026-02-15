//
//  LogRExampleApp.swift
//  LogRExample
//
//  Created by martin on 25/11/2025.
//

import Logr
import LogrUI
import SwiftUI

@main
struct LogRExampleApp: App {
    @State private var logger: LogR

    init() {
        do {
            let storage = try SQLiteStorage()
            let config = LogrConfiguration(maxLogEntries: 10_000,
                                           maxLogAge: 7 * 24 * 60 * 60,
                                           enabledLevels: Set(LogLevel.allCases),
                                           subsystem: "me.martin.example.LogRExample",
                                           cleanupInterval: 60 * 60,
                                           logVerbosity: .verbose)
            if #available(macOS 26.0, *) {
                let logr = try LogR(storage: storage,
                                    logAnalyser: AIAnalyzer(),
                                    configuration: config)
                _logger = State(initialValue: logr)
            } else {
                let logr = try LogR(storage: storage, configuration: config)
                _logger = State(initialValue: logr)
            }
        } catch {
            fatalError("Could not initialize LogR: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(\.logService, logger)
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") {
                NavigationStack {
                    ContentView()
                }
            }

            Tab("Log Demo", systemImage: "square.and.pencil") {
                NavigationStack {
                    LogDemoView()
                }
            }

            Tab("Log Viewer", systemImage: "list.bullet.rectangle") {
                NavigationStack {
                    LogViewer()
                }
            }

            if #available(macOS 26.0, *) {
                Tab("Analysis", systemImage: "waveform.badge.magnifyingglass") {
                    NavigationStack {
                        LogAnalysisView()
                    }
                }
            }

            Tab("Settings", systemImage: "gear") {
                NavigationStack {
                    SettingsView()
                }
            }
        }
    }
}

#Preview {
    MainTabView()
        .environment(\.logService, try! LogR())
}
