import Foundation
import SwiftUI

///// Example usage patterns for LogR
//public enum LogRExamples {
//    
//    /// Basic logging example
//    public static func basicLogging() async {
////        // Simple logging with different levels
////        await LogR.shared.debug("Starting application initialization")
////        await LogR.shared.info("User interface loaded successfully")
////        await LogR.shared.notice("Background sync starting")
////        await LogR.shared.error("Failed to load user preferences")
////        await LogR.shared.fault("Critical system error occurred")
//    }
//    
//    /// Categorized logging example
//    public static func categorizedLogging() async {
////        // Organize logs by feature/component
////        await LogR.shared.info("Network request started", category: "networking")
////        await LogR.shared.debug("Parsing JSON response", category: "networking")
////        await LogR.shared.error("Network timeout", category: "networking")
////        
////        await LogR.shared.info("View appeared", category: "ui")
////        await LogR.shared.debug("Button tapped", category: "ui")
////        
////        await LogR.shared.info("User logged in", category: "authentication")
////        await LogR.shared.error("Invalid credentials", category: "authentication")
//    }
//    
//    /// Privacy-aware logging example
//    public static func privacyAwareLogging() async {
//        // Handle sensitive data properly
//        let username = PrivateString("john.doe@example.com", privacy: .private)
//        let apiKey = PrivateString("sk_live_abc123xyz789", privacy: .sensitive)
//        let publicInfo = PrivateString("Welcome message", privacy: .public)
////        
////        await LogR.shared.info("User login attempt for", privateData: username)
////        await LogR.shared.debug("Using API key", privateData: apiKey)
////        await LogR.shared.info("Displaying", privateData: publicInfo)
//    }
//    
//    /// Custom configuration example
//    @MainActor
//    public static func customConfiguration() -> LogR {
//        let config = LogrConfiguration(
//            maxLogEntries: 5000,          // Keep 5000 entries max
//            maxLogAge: 24 * 60 * 60,      // Keep logs for 24 hours
//            enabledLevels: [.info, .error, .fault], // Only log important events
//            subsystem: "com.myapp.main",
//            cleanupInterval: 30 * 60      // Cleanup every 30 minutes
//        )
//        
//        return LogR(configuration: config)
//    }
//    
//    /// Filtering and querying logs example
//    public static func filteringLogs() async throws {
//        // Create a logger instance for this example
//        let logger = LogR()
//        
//        // Add some test logs
//        await logger.info("User action", category: .ui)
//        await logger.error("Network error", category: .network)
//        await logger.debug("Debug info", category: .debug)
//        
//        // Filter by log level
//        let errorLogs = try await logger.getLogs(levels: [LogLevel.error, LogLevel.fault])
//        print("Found \(errorLogs.count) error/fault logs")
//        
//        // Filter by category
//        let networkLogs = try await logger.getLogs(categories: [LogCategory.network])
//        print("Found \(networkLogs.count) networking logs")
//        
//        // Filter by date range
//        let today = Date()
//        let yesterday = today.addingTimeInterval(-24 * 60 * 60)
//        let recentLogs = try await logger.getLogs(from: yesterday, to: today)
//        print("Found \(recentLogs.count) logs from last 24 hours")
//        
//        // Combine filters
//        let recentNetworkErrors = try await logger.getLogs(
//            levels: [LogLevel.error],
//            categories: [LogCategory.network],
//            from: yesterday,
//            to: today,
//            limit: 10
//        )
//        print("Found \(recentNetworkErrors.count) recent network errors")
//    }
//    
//    /// Export logs example
//    public static func exportingLogs() async throws {
//        // Create a logger instance for this example
//        let logger = LogR()
//        
//        // Export in different formats
//        let jsonData = try await logger.exportLogs(format: ExportFormat.json)
//        let csvData = try await logger.exportLogs(format: ExportFormat.csv)
//        let textData = try await logger.exportLogs(format: ExportFormat.txt)
//        
//        // Save to files (in a real app, you might use document picker)
//        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
//        
//        try jsonData.write(to: documentsPath.appendingPathComponent("logs.json"))
//        try csvData.write(to: documentsPath.appendingPathComponent("logs.csv"))
//        try textData.write(to: documentsPath.appendingPathComponent("logs.txt"))
//        
//        print("Logs exported to Documents directory")
//    }
//    
//    /// Configuration management example
//    public static func configurationManagement() async throws {
//        let configManager = try ConfigurationManager()
//        
//        // Load current configuration
//        let currentConfig = try await configManager.loadConfiguration()
//        print("Current max entries: \(currentConfig.maxLogEntries)")
//        
//        // Update a specific setting
//        try await configManager.updateConfiguration(\.maxLogEntries, value: 2000)
//        
//        // Create and save a custom configuration
//        let customConfig = LogrConfiguration(
//            maxLogEntries: 1000,
//            maxLogAge: 2 * 24 * 60 * 60, // 2 days
//            enabledLevels: [.info, .error, .fault],
//            subsystem: "com.myapp.custom"
//        )
//        try await configManager.saveConfiguration(customConfig)
//        
//        // Reset to default
//        try await configManager.resetToDefault()
//    }
//}
//
///// Example SwiftUI views using LogR
//public struct LogRSwiftUIExamples {
//    
//    /// Basic log viewer integration
//    public struct BasicLogViewer: View {
//        public init() {}
//        
//        public var body: some View {
//            NavigationStack {
//                LogViewer()
//            }
//        }
//    }
//    
//    /// Custom logger with logging controls
//    public struct LoggingControlsView: View {
//        @Environment(\.logr) private var logger
//        @State private var message = ""
//        @State private var selectedLevel = LogLevel.info
//        @State private var category = "demo"
//        
//        public init() {}
//        
//        public var body: some View {
//            VStack(spacing: 20) {
//                TextField("Log message", text: $message)
//                    .textFieldStyle(RoundedBorderTextFieldStyle())
//                
//                HStack {
//                    Text("Level:")
//                    Picker("Level", selection: $selectedLevel) {
//                        ForEach(LogLevel.allCases, id: \.self) { level in
//                            Text(level.displayName).tag(level)
//                        }
//                    }
//                    .pickerStyle(SegmentedPickerStyle())
//                }
//                
//                TextField("Category", text: $category)
//                    .textFieldStyle(RoundedBorderTextFieldStyle())
//                
//                Button("Log Message") {
//                    Task {
//                        await logger.log(
//                            level: selectedLevel,
//                            message: message,
//                            category: LogCategory(rawValue: category),
//                            file: #file,
//                            function: #function,
//                            line: #line
//                        )
//                        message = ""
//                    }
//                }
//                .disabled(message.isEmpty)
//                
//                NavigationLink("View Logs") {
//                    LogViewer(logr: logger)
//                }
//                
//                Spacer()
//            }
//            .padding()
//            .navigationTitle("LogR Demo")
//        }
//    }
//    
//    /// App-wide logging integration example
//    public struct AppWithLogging: View {
//        @Environment(\.logr) private var logger
//        
//        public init() {}
//        
//        public var body: some View {
//            TabView {
//                ContentView()
//                    .tabItem {
//                        Image(systemName: "house")
//                        Text("Home")
//                    }
//                
//                LogViewer(logr: logger)
//                    .tabItem {
//                        Image(systemName: "list.bullet.rectangle")
//                        Text("Logs")
//                    }
//            }
//            .task {
//                await logger.info("Application launched", category: .lifecycle)
//            }
//        }
//        
//        struct ContentView: View {
//            var body: some View {
//                VStack {
//                    Text("Main App Content")
//                    Button("Trigger Log") {
//                        Task {
//                            await LogR().info("Button tapped", category: .ui)
//                        }
//                    }
//                }
//                .navigationTitle("App")
//            }
//        }
//    }
//}
//
//#Preview("Basic Log Viewer") {
//    LogRSwiftUIExamples.BasicLogViewer()
//}
//
//#Preview("Logging Controls") {
//    NavigationStack {
//        LogRSwiftUIExamples.LoggingControlsView()
//    }
//}
//
//#Preview("App with Logging") {
//    LogRSwiftUIExamples.AppWithLogging()
//}
