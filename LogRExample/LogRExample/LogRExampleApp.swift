//
//  LogRExampleApp.swift
//  LogRExample
//
//  Created by martin on 25/11/2025.
//

import Logr
import LogrNetwork
import LogrUI
import SwiftUI

@main
struct LogRExampleApp: App {
    @State private var logger: LogR
    private let networkLogger: NetworkLogger

    init() {
        let config = LogrConfiguration(maxLogEntries: 10_000,
                                       maxLogAge: 7 * 24 * 60 * 60,
                                       enabledLevels: Set(LogLevel.allCases),
                                       subsystem: "me.martin.example.LogRExample",
                                       cleanupInterval: 60 * 60,
                                       logVerbosity: .verbose)
        let logger = if #available(macOS 26.0, *) {
            LogR(storage: .sqlite(), logAnalyser: AIAnalyzer(), configuration: config)
        } else {
            LogR(storage: .sqlite(), configuration: config)
        }
        _logger = State(initialValue: logger)
        networkLogger = NetworkLogger(logger: logger,
                                      configuration: NetworkLoggerConfiguration(captureBodies: true))
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(\.logService, logger)
                .environment(\.networkLogger, networkLogger)
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
        .environment(\.logService, LogR())
}
