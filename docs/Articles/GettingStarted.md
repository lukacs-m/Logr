---
layout: default
title: Getting Started
nav_order: 2
parent: Logr Documentation
---

# Getting Started with Logr

Learn how to integrate Logr into your app and start logging immediately.

[← Back to Documentation](../index.md)

## Overview

This guide will walk you through adding Logr to your project, configuring it, and using it to log messages in your application.

## Installation

### Swift Package Manager

Add Logr to your project using Swift Package Manager:

**In Xcode:**
1. File → Add Package Dependencies
2. Enter: `https://github.com/lukacs-m/logr`
3. Select the desired version
4. Add `Logr` and optionally `LogrUI` to your target

**In Package.swift:**
```swift
dependencies: [
    .package(url: "https://github.com/lukacs-m/logr", from: "1.0.0")
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: ["Logr", "LogrUI"]
    )
]
```

## Basic Setup

### Without Persistent Storage

For quick setup without persistence (OSLog only):

```swift
import SwiftUI
import Logr

@main
struct MyApp: App {
    let logger = try! LogR()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .logRService(logger)
        }
    }
}
```

### With Persistent Storage

For production apps with persistent, encrypted storage:

```swift
import SwiftUI
import Logr

@main
struct MyApp: App {
    // SQLite storage (recommended for large volumes)
    let logger = try LogR(storage: SQLiteStorage())

    // Or FileSystem storage (simple JSON files)
    // let logger = try! LogR(storage: FileSystemStorage())

    var body: some Scene {
        WindowGroup {
            ContentView()
                .logRService(logger)
        }
    }
}
```

## Your First Logs

### In SwiftUI Views

Access the logger through the environment:

```swift
import SwiftUI
import Logr

struct ContentView: View {
    @Environment(\.logService) private var logger

    var body: some View {
        VStack {
            Button("Do Something") {
                logger.info("Button tapped", category: .ui)
                performAction()
            }
        }
        .onAppear {
            logger.info("ContentView appeared", category: .lifecycle)
        }
    }

    private func performAction() {
        logger.debug("Starting action", category: .user)

        // Perform your action
        do {
            try riskyOperation()
            logger.info("Action completed successfully", category: .user)
        } catch {
            logger.error("Action failed: \(error)", category: .user)
        }
    }
}
```

### Outside SwiftUI

Keep a reference to the logger:

```swift
import Logr

class NetworkManager {
    private let logger: LogRService

    init(logger: LogRService) {
        self.logger = logger
    }

    func fetchData() async throws -> Data {
        logger.info("Fetching data from API", category: .network)

        do {
            let data = try await performRequest()
            logger.info("Data fetched successfully", category: .network)
            return data
        } catch {
            logger.error("Failed to fetch data: \(error)", category: .network)
            throw error
        }
    }
}
```

## Using Log Levels

Logr provides six log levels to categorize message severity:

```swift
// Debug - detailed information for development
logger.debug("Cache contains \(cache.count) items", category: .cache)

// Info - general information about app state
logger.info("User logged in successfully", category: .authentication)

// Notice - significant but expected events
logger.notice("Payment processed: $\(amount)", category: .payment)

// Warning - unexpected but non-fatal conditions
logger.warning("API response took \(duration)s", category: .network)

// Error - significant failures
logger.error("Failed to save data: \(error)", category: .database)

// Fault - critical system errors
logger.fault("Database connection lost", category: .database)
```

## Using Categories

Organize your logs using the 47+ predefined categories:

```swift
// Networking
logger.info("API request started", category: .network)
logger.debug("Request headers: \(headers)", category: .http)
logger.error("SSL certificate invalid", category: .ssl)

// User Interface
logger.debug("View loaded", category: .ui)
logger.info("Navigation to profile", category: .navigation)
logger.warning("Layout constraint conflict", category: .layout)

// Data & Storage
logger.info("Database query completed", category: .database)
logger.debug("Cache hit for key: \(key)", category: .cache)
logger.error("Failed to write file", category: .fileSystem)

// Security
logger.info("User authenticated", category: .authentication)
logger.error("Permission denied", category: .authorization)
logger.warning("Keychain access failed", category: .keychain)

// Custom categories for your specific needs
logger.info("Inventory updated", category: .custom("inventory"))
```

## Adding the Log Viewer

Include the SwiftUI log viewer in your app:

```swift
import SwiftUI
import Logr
import LogrUI

@main
struct MyApp: App {
    let logger = try! LogR(storage: SQLiteStorage())

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                    .tabItem {
                        Label("Home", systemImage: "house")
                    }

                NavigationStack {
                    LogViewer()
                }
                .tabItem {
                    Label("Logs", systemImage: "list.bullet")
                }
            }
            .logRService(logger)
        }
    }
}
```

## Configuration

Customize Logr behavior with configuration:

```swift
let config = LogrConfiguration(
    maxLogEntries: 5_000,              // Keep 5,000 most recent logs
    maxLogAge: 24 * 60 * 60,           // Keep logs for 24 hours
    enabledLevels: [.info, .warning, .error, .fault], // Only important logs
    subsystem: "com.myapp.logging",    // Your app's subsystem
    cleanupInterval: 30 * 60,          // Clean up every 30 minutes
    logVerbosity: .normal              // Normal verbosity (no source location)
)

let logger = try LogR(
    storage: SQLiteStorage(),
    configuration: config
)
```

### Development vs Production

Use different configurations for different environments:

```swift
@main
struct MyApp: App {
    let logger: LogR = {
        #if DEBUG
        // Development: verbose logging with all levels
        let config = LogrConfiguration(
            maxLogEntries: 10_000,
            maxLogAge: 7 * 24 * 60 * 60,
            enabledLevels: Set(LogLevel.allCases),
            logVerbosity: .verbose
        )
        #else
        // Production: only important logs, less detail
        let config = LogrConfiguration(
            maxLogEntries: 5_000,
            maxLogAge: 24 * 60 * 60,
            enabledLevels: [.info, .warning, .error, .fault],
            logVerbosity: .normal
        )
        #endif

        return try LogR(storage: SQLiteStorage(), configuration: config)
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .logRService(logger)
        }
    }
}
```

## Next Steps

Now that you have Logr set up, explore these topics:

- [Architecture](./Architecture.md) - Understand how Logr works internally
- [Storage and Persistence](./StorageAndPersistence.md) - Learn about storage options and custom implementations
- [Privacy and Security](./PrivacyAndSecurity.md) - Understand encryption and privacy features
- [SwiftUI Integration](./SwiftUIIntegration.md) - Explore the full LogViewer capabilities
- [AI Analysis](./AIAnalysis.md) - Use AI-powered log analysis (iOS 26+)
- [Testing and Mocking](./TestingAndMocking.md) - Test your logging with `MockLogR`

## Common Patterns

### Error Handling

```swift
func loadData() async {
    logger.debug("Loading data", category: .database)

    do {
        let data = try await database.load()
        logger.info("Data loaded: \(data.count) items", category: .database)
    } catch let error as DatabaseError {
        logger.error("Database error: \(error.localizedDescription)", category: .database)
    } catch {
        logger.fault("Unexpected error: \(error)", category: .system)
    }
}
```

### Network Requests

```swift
func performRequest() async throws -> Response {
    logger.info("Starting API request", category: .network)
    let startTime = Date()

    do {
        let response = try await urlSession.data(from: url)
        let duration = Date().timeIntervalSince(startTime)

        if duration > 2.0 {
            logger.warning("Slow API response: \(duration)s", category: .performance)
        }

        logger.info("Request completed in \(duration)s", category: .network)
        return response
    } catch {
        logger.error("Request failed: \(error)", category: .network)
        throw error
    }
}
```

### Lifecycle Events

```swift
@main
struct MyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    let logger = try! LogR(storage: SQLiteStorage())

    var body: some Scene {
        WindowGroup {
            ContentView()
                .logRService(logger)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                logger.info("App became active", category: .lifecycle)
            case .inactive:
                logger.info("App became inactive", category: .lifecycle)
            case .background:
                logger.info("App entered background", category: .lifecycle)
                Task {
                    await logger.flush() // Ensure logs are written
                }
            @unknown default:
                break
            }
        }
    }
}
```
