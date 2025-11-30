//
//  LogDemoView.swift
//  LogRExample
//
//  Demonstrates all logging capabilities of the LogR library.
//

import Logr
import SwiftUI

struct LogDemoView: View {
    @Environment(\.logService) private var logger

    @State private var customMessage = ""
    @State private var selectedLevel: LogLevel = .info
    @State private var selectedCategory: LogCategory = .system
    @State private var batchCount = 10

    var body: some View {
        List {
            quickActionsSection
            logLevelsSection
            categoriesSection
            customLogSection
            batchLoggingSection
            scenarioSection
        }
        .navigationTitle("Log Demo")
        .onAppear {
            logger.info("LogDemoView appeared", category: .ui)
        }
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        Section {
            Button {
                logAllLevels()
            } label: {
                Label("Log All Levels", systemImage: "square.stack.3d.up.fill")
            }

            Button {
                logAllCategories()
            } label: {
                Label("Log All Categories", systemImage: "folder.fill")
            }

            Button {
                logPerformanceMetrics()
            } label: {
                Label("Log Performance Metrics", systemImage: "gauge.with.dots.needle.bottom.50percent")
            }
        } header: {
            Text("Quick Actions")
        } footer: {
            Text("Quickly generate sample logs to test the viewer.")
        }
    }

    // MARK: - Log Levels

    private var logLevelsSection: some View {
        Section {
            ForEach(LogLevel.allCases) { level in
                Button {
                    logAtLevel(level)
                } label: {
                    HStack {
                        Text(level.visualQueue)
                        Text(level.displayName)
                            .foregroundStyle(colorForLevel(level))
                        Spacer()
                        Text("Priority: \(level.priority)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Log Levels")
        } footer: {
            Text("Tap a level to create a sample log entry at that severity.")
        }
    }

    // MARK: - Categories

    private var categoriesSection: some View {
        Section {
            DisclosureGroup("System & Core") {
                categoryButtons([.system, .lifecycle, .initialization, .configuration])
            }

            DisclosureGroup("Networking") {
                categoryButtons([.network, .api, .http, .websocket])
            }

            DisclosureGroup("User Interface") {
                categoryButtons([.ui, .navigation, .animation, .layout])
            }

            DisclosureGroup("Data & Storage") {
                categoryButtons([.database, .coreData, .fileSystem, .cache, .persistence])
            }

            DisclosureGroup("Security") {
                categoryButtons([.authentication, .authorization, .security, .encryption])
            }

            DisclosureGroup("Performance") {
                categoryButtons([.performance, .memory, .cpu, .analytics])
            }
        } header: {
            Text("Categories")
        } footer: {
            Text("LogR provides 47 predefined categories organized by domain.")
        }
    }

    @ViewBuilder
    private func categoryButtons(_ categories: [LogCategory]) -> some View {
        ForEach(categories) { category in
            Button {
                logger.info("Sample log for \(category.rawValue) category", category: category)
            } label: {
                Text(category.rawValue)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Custom Log

    private var customLogSection: some View {
        Section {
            Picker("Level", selection: $selectedLevel) {
                ForEach(LogLevel.allCases, id: \.self) { level in
                    Text(level.displayName).tag(level)
                }
            }

            Picker("Category", selection: $selectedCategory) {
                ForEach(LogCategory.common, id: \.rawValue) { category in
                    Text(category.rawValue).tag(category)
                }
            }

            TextField("Message", text: $customMessage)
                .textFieldStyle(.roundedBorder)

            Button {
                guard !customMessage.isEmpty else { return }
                logger.log(level: selectedLevel,
                           message: customMessage,
                           category: selectedCategory,
                           file: #file,
                           function: #function,
                           line: #line)
                customMessage = ""
            } label: {
                Label("Send Custom Log", systemImage: "paperplane.fill")
            }
            .disabled(customMessage.isEmpty)
        } header: {
            Text("Custom Log Entry")
        } footer: {
            Text("Create your own log entry with custom level, category, and message.")
        }
    }

    // MARK: - Batch Logging

    private var batchLoggingSection: some View {
        Section {
            Stepper("Count: \(batchCount)", value: $batchCount, in: 1...100)

            Button {
                generateBatchLogs()
            } label: {
                Label("Generate \(batchCount) Random Logs", systemImage: "arrow.3.trianglepath")
            }
        } header: {
            Text("Batch Logging")
        } footer: {
            Text("Generate multiple logs at once to test performance and scrolling.")
        }
    }

    // MARK: - Scenario Simulation

    private var scenarioSection: some View {
        Section {
            Button {
                simulateAppLaunch()
            } label: {
                Label("Simulate App Launch", systemImage: "power")
            }

            Button {
                simulateNetworkRequest()
            } label: {
                Label("Simulate Network Request", systemImage: "network")
            }

            Button {
                simulateAuthFlow()
            } label: {
                Label("Simulate Auth Flow", systemImage: "person.badge.key.fill")
            }

            Button {
                simulateError()
            } label: {
                Label("Simulate Error Scenario", systemImage: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(.red)

            Button {
                simulatePrivacyIssue()
            } label: {
                Label("Simulate Privacy Issue (Test)", systemImage: "eye.slash.fill")
            }
            .foregroundStyle(.orange)
        } header: {
            Text("Scenario Simulation")
        } footer: {
            Text("Simulate real-world logging scenarios to see how LogR handles them.")
        }
    }

    // MARK: - Helper Methods

    private func colorForLevel(_ level: LogLevel) -> Color {
        switch level {
        case .debug: .purple
        case .info: .blue
        case .notice: .cyan
        case .warning: .yellow
        case .error: .orange
        case .fault: .red
        }
    }

    private func logAtLevel(_ level: LogLevel) {
        let messages: [LogLevel: String] = [
            .debug: "Debugging view hierarchy layout calculation",
            .info: "User navigated to LogDemoView",
            .notice: "Configuration loaded successfully",
            .warning: "Cache is reaching capacity limit",
            .error: "Failed to save user preferences",
            .fault: "Critical: Database connection lost"
        ]

        logger.log(level: level,
                   message: messages[level] ?? "Sample \(level.displayName) message",
                   category: .system,
                   file: #file,
                   function: #function,
                   line: #line)
    }

    private func logAllLevels() {
        logger.debug("Debug: Detailed trace information for development", category: .debug)
        logger.info("Info: General application state update", category: .system)
        logger.notice("Notice: Significant but expected event occurred", category: .lifecycle)
        logger.warning("Warning: Potential issue detected, but recovered", category: .performance)
        logger.error("Error: Operation failed, feature may be degraded", category: .network)
        logger.fault("Fault: Critical system error requiring attention", category: .system)
    }

    private func logAllCategories() {
        let sampleCategories: [LogCategory] = [
            .system, .network, .ui, .database, .authentication, .performance
        ]

        for category in sampleCategories {
            logger.info("Sample log for \(category.rawValue) category", category: category)
        }

        logger.info("Custom category example", category: .custom("feature-flags"))
    }

    private func logPerformanceMetrics() {
        logger.debug("CPU Usage: 23%", category: .cpu)
        logger.debug("Memory: 145MB / 512MB", category: .memory)
        logger.info("Frame rate: 60fps (stable)", category: .performance)
        logger.notice("Battery: 78% (not charging)", category: .battery)
        logger.debug("Network latency: 45ms", category: .network)
        logger.info("Cache hit ratio: 94%", category: .cache)
    }

    private func generateBatchLogs() {
        let levels = LogLevel.allCases
        let categories: [LogCategory] = [.system, .network, .ui, .database, .performance, .cache]
        let messages = [
            "Processing request",
            "Data synchronized",
            "View rendered",
            "Cache updated",
            "Background task completed",
            "User action recorded",
            "State changed",
            "Timer fired",
            "Notification received",
            "Resource loaded"
        ]

        for i in 0..<batchCount {
            let level = levels.randomElement() ?? .info
            let category = categories.randomElement() ?? .system
            let message = messages.randomElement() ?? "Log entry"
            logger.log(level: level,
                       message: "\(message) #\(i + 1)",
                       category: category,
                       file: #file,
                       function: #function,
                       line: #line)
        }
    }

    private func simulateAppLaunch() {
        logger.info("Application launched", category: .lifecycle)
        logger.debug("Loading configuration...", category: .configuration)
        logger.debug("Initializing services...", category: .initialization)
        logger.info("Database connection established", category: .database)
        logger.debug("Loading cached data...", category: .cache)
        logger.info("User session restored", category: .authentication)
        logger.notice("Application ready", category: .lifecycle)
    }

    private func simulateNetworkRequest() {
        logger.debug("Preparing API request to /api/v1/users", category: .api)
        logger.debug("Adding authorization header", category: .http)
        logger.info("Sending GET request", category: .network)
        logger.debug("Response received: 200 OK", category: .http)
        logger.debug("Parsing JSON response...", category: .api)
        logger.info("Successfully fetched 25 users", category: .network)
        logger.debug("Updating local cache", category: .cache)
    }

    private func simulateAuthFlow() {
        logger.info("User initiated login", category: .authentication)
        logger.debug("Validating credentials format", category: .authorization)
        logger.debug("Checking biometric availability", category: .biometrics)
        logger.info("Biometric authentication successful", category: .biometrics)
        logger.debug("Generating session token", category: .security)
        logger.debug("Storing credentials in keychain", category: .keychain)
        logger.notice("User authenticated successfully", category: .authentication)
    }

    private func simulateError() {
        logger.info("Attempting to sync data", category: .sync)
        logger.debug("Checking network connectivity", category: .network)
        logger.warning("Network connection unstable", category: .network)
        logger.error("Sync failed: Connection timeout after 30s", category: .sync)
        logger.debug("Scheduling retry in 60 seconds", category: .system)
        logger.warning("Data may be out of date", category: .cache)
        logger.fault("Critical: Multiple sync failures detected", category: .system)
    }

    private func simulatePrivacyIssue() {
        logger.warning("User email: test@example.com (DEMO - not real PII)", category: .user)
        logger.debug("Session token: abc123xyz789 (DEMO)", category: .authentication)
        logger.info("User location: 37.7749, -122.4194 (DEMO - SF coordinates)", category: .location)
        logger.notice("These are demonstration logs to test privacy scanning", category: .debug)
    }
}

#Preview {
    NavigationStack {
        LogDemoView()
    }
    .environment(\.logService, LogR())
}
