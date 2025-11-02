# LogR

[![Swift Package Manager Compatible](https://img.shields.io/badge/SPM-compatible-4BC51D.svg?style=flat)](https://swift.org/package-manager/)
[![Platform](https://img.shields.io/badge/platforms-iOS%2017.0%20%7C%20macOS%2014.0%20%7C%20tvOS%2017.0%20%7C%20watchOS%2010.0-333333.svg)](https://developer.apple.com/swift)
[![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)

A powerful, persistent logging library for Apple platforms that leverages OSLog while providing persistent storage and beautiful SwiftUI visualization.

## 🌟 Features

- **🔄 Persistent Logging**: Unlike standard OSLog entries that are cleared between sessions, LogR maintains logs persistently
- **📱 SwiftUI Integration**: Beautiful, built-in log viewer with filtering, search, and sharing capabilities  
- **🔒 Privacy-Aware**: Full support for Apple's privacy operators for sensitive data
- **⚙️ Configurable**: Flexible configuration for log retention, levels, and cleanup
- **🏗️ Dependency Injection**: Protocol-based architecture perfect for modern Swift apps
- **📂 Category System**: Comprehensive enum-based categories with custom support
- **🧪 Testing Ready**: Built-in mock implementation for SwiftUI previews and testing
- **🚀 Swift 6.2 Compatible**: Built with the latest Swift concurrency and safety features

## 📋 Table of Contents

- [Installation](#-installation)
- [Quick Start](#-quick-start)
- [Category System](#-category-system)
- [SwiftUI Integration](#-swiftui-integration)
- [Privacy & Security](#-privacy--security)
- [Configuration](#-configuration)
- [Dependency Injection](#-dependency-injection)
- [Testing & Previews](#-testing--previews)
- [Advanced Usage](#-advanced-usage)
- [API Reference](#-api-reference)

## 📦 Installation

### Swift Package Manager

Add LogR to your project through Xcode:

1. File → Add Package Dependencies
2. Enter: `https://github.com/yourorg/logr`
3. Select the version and add to your target

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourorg/logr", from: "1.0.0")
]
```

### Platform Support

- **iOS** 17.0+
- **macOS** 14.0+
- **tvOS** 17.0+
- **watchOS** 10.0+

## 🚀 Quick Start

### Basic Setup

```swift
import LogR
import SwiftUI

@main
struct MyApp: App {
    let logger = LogR()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .logRService(logger)
        }
    }
}
```

### Basic Logging

```swift
struct ContentView: View {
    @Environment(\.logr) private var logger
    
    var body: some View {
        VStack {
            Button("Log Something") {
                Task {
                    await logger.info("Button was tapped", category: .ui)
                    await logger.debug("Processing user action", category: .ui)
                }
            }
            
            NavigationLink("View Logs") {
                LogViewer()
            }
        }
    }
}
```

## 🏷️ Category System

LogR provides a comprehensive category system for organizing your logs:

### Predefined Categories

```swift
// System & Core
.system, .lifecycle, .initialization, .configuration

// Networking  
.network, .api, .http, .websocket, .ssl

// User Interface
.ui, .navigation, .animation, .layout, .gesture

// Data & Storage
.database, .coreData, .fileSystem, .cache, .persistence, .sync

// Security & Authentication
.authentication, .authorization, .security, .encryption, .keychain, .biometrics

// Performance & Monitoring
.performance, .memory, .cpu, .battery, .analytics, .crash, .profiling

// External Services
.push, .location, .camera, .microphone, .contacts, .calendar, .photos

// Business Logic
.payment, .subscription, .purchase, .user, .content, .search

// Development & Testing
.debug, .test, .mock
```

### Custom Categories

```swift
// For project-specific needs
await logger.info("Custom business logic", category: .custom("inventory-management"))
await logger.debug("Special feature activated", category: .custom("feature-flags"))
```

### Usage Examples

```swift
// Networking
await logger.info("API request started", category: .network)
await logger.error("Request failed", category: .api)

// UI Events
await logger.debug("View appeared", category: .ui)
await logger.info("Navigation completed", category: .navigation)

// Performance
await logger.notice("Memory usage: 45MB", category: .performance)
await logger.debug("CPU usage: 12%", category: .cpu)

// Security
await logger.error("Authentication failed", category: .authentication)
await logger.fault("Security breach detected", category: .security)
```

## 📱 SwiftUI Integration

### Environment-Based Usage

LogR uses SwiftUI's environment system for clean dependency injection:

```swift
import SwiftUI
import LogR

struct MyApp: App {
    let logger = LogR()
    
    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                    .tabItem { Label("Home", systemImage: "house") }
                
                LogViewer()
                    .tabItem { Label("Logs", systemImage: "list.bullet") }
            }
            .logRService(logger)
        }
    }
}

struct ContentView: View {
    @Environment(\.logr) private var logger
    
    var body: some View {
        VStack {
            Button("Test Logging") {
                Task {
                    await logger.info("User tapped test button", category: .ui)
                    await logger.debug("Processing test action", category: .debug)
                }
            }
        }
        .onAppear {
            Task {
                await logger.info("ContentView appeared", category: .lifecycle)
            }
        }
    }
}
```

### Log Viewer Features

The built-in `LogViewer` provides:

- **📊 Real-time log display** with automatic updates
- **🔍 Search functionality** across messages, categories, and subsystems
- **🏷️ Advanced filtering** by log levels and categories
- **📤 Share & Export** logs in JSON, CSV, or plain text formats
- **🗂️ Organized actions** in contextual menus
- **🎨 Clean, readable interface** with color-coded log levels

```swift
NavigationView {
    LogViewer()
}
```

## 🔒 Privacy & Security

LogR fully supports Apple's privacy system for handling sensitive data:

### Privacy Levels

```swift
import LogR

// Public data (visible in logs)
let publicData = PrivateString("Welcome message", privacy: .public)

// Private data (redacted in persistent storage, visible in OSLog)
let privateData = PrivateString("user@example.com", privacy: .private)

// Sensitive data (redacted everywhere)
let sensitiveData = PrivateString("sk_live_abc123", privacy: .sensitive)
```

### Usage Examples

```swift
let userEmail = PrivateString("john@example.com", privacy: .private)
let apiKey = PrivateString("sk_live_abc123xyz", privacy: .sensitive)

await logger.info("User logged in", privateData: userEmail, category: .authentication)
await logger.debug("API request authenticated", privateData: apiKey, category: .network)

// In persistent storage: "User logged in <private>"
// In OSLog: "User logged in john@example.com" (with proper privacy marking)
```

## ⚙️ Configuration

### Custom Configuration

```swift
let config = LogrConfiguration(
    maxLogEntries: 5_000,               // Keep up to 5,000 log entries
    maxLogAge: 24 * 60 * 60,           // Keep logs for 24 hours
    enabledLevels: [.info, .error, .fault], // Only log important events
    subsystem: "com.myapp.logging",     // Your app's subsystem
    cleanupInterval: 30 * 60            // Clean up every 30 minutes
)

let logger = LogR(configuration: config)
```

### Configuration Options

```swift
public struct LogrConfiguration {
    public let maxLogEntries: Int       // Maximum number of log entries to keep
    public let maxLogAge: TimeInterval  // Maximum age of log entries (in seconds)
    public let enabledLevels: Set<LogLevel> // Which log levels to process
    public let subsystem: String        // OSLog subsystem identifier
    public let cleanupInterval: TimeInterval // How often to run cleanup (in seconds)
}
```

### Default Configuration

```swift
LogrConfiguration.default // Sensible defaults for most apps:
// - maxLogEntries: 10,000
// - maxLogAge: 7 days  
// - enabledLevels: all levels
// - subsystem: Bundle.main.bundleIdentifier
// - cleanupInterval: 1 hour
```

## 🏗️ Dependency Injection

LogR is designed with dependency injection in mind, avoiding singletons for better architecture:

### Basic Setup

```swift
// In your app's dependency container
protocol Dependencies {
    var logger: LogRService { get }
}

class AppDependencies: Dependencies {
    lazy var logger: LogRService = LogR(
        configuration: LogrConfiguration(
            subsystem: "com.myapp.main"
        )
    )
}

// Inject into SwiftUI
@main
struct MyApp: App {
    let dependencies = AppDependencies()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .logRService(dependencies.logger)
        }
    }
}
```

### With Popular DI Frameworks

#### Resolver

```swift
import Resolver

extension Resolver: ResolverRegistering {
    public static func registerAllServices() {
        register { LogR() as LogRService }
            .scope(.application)
    }
}
```

#### Factory

```swift
import Factory

extension Container {
    var logger: Factory<LogRService> {
        self { LogR() }
            .singleton
    }
}
```

## 🧪 Testing & Previews

LogR includes a full-featured mock implementation for testing and SwiftUI previews:

### SwiftUI Previews

```swift
#Preview {
    NavigationStack {
        LogViewer()
    }
    // MockLogR is automatically used via environment default
}

#Preview("With Custom Logger") {
    let mockLogger = MockLogR()
    
    return ContentView()
        .logRService(mockLogger)
}
```

### Unit Testing

```swift
import XCTest
@testable import LogR

class MyViewModelTests: XCTestCase {
    var mockLogger: MockLogR!
    var viewModel: MyViewModel!
    
    override func setUp() {
        mockLogger = MockLogR()
        viewModel = MyViewModel(logger: mockLogger)
    }
    
    func testLoggingBehavior() async {
        await viewModel.performAction()
        
        // Verify logs were created
        XCTAssertFalse(mockLogger.recentLogs.isEmpty)
        
        // Check specific log content
        let logs = try await mockLogger.getLogs(categories: [.ui])
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.message, "Action performed")
    }
}
```

### MockLogR Features

- ✅ Full `LogRService` protocol compliance
- 📊 Pre-populated with realistic sample data
- 🔄 Maintains in-memory log history
- 🎯 Perfect for previews and testing
- 🚀 Zero setup required

## 🎯 Advanced Usage

### Custom Storage Implementation

```swift
import LogR

class CloudStorage: PersistentStorage {
    func store(_ entry: LogEntry) async throws {
        // Upload to your cloud service
    }
    
    func retrieve(/* parameters */) async throws -> [LogEntry] {
        // Fetch from your cloud service
    }
    
    // Implement other required methods...
}

let logger = LogR(storage: CloudStorage())
```

### Filtering & Querying

```swift
// Get logs from the last hour with specific categories
let recentErrors = try await logger.getLogs(
    levels: [.error, .fault],
    categories: [.network, .api],
    from: Date().addingTimeInterval(-3600),
    to: Date(),
    limit: 50
)

// Get all authentication-related logs
let authLogs = try await logger.getLogs(
    categories: [.authentication, .authorization, .security]
)
```

### Programmatic Export

```swift
// Export logs in different formats
let jsonData = try await logger.exportLogs(format: .json)
let csvData = try await logger.exportLogs(format: .csv) 
let textData = try await logger.exportLogs(format: .txt)

// Save to files
let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
try jsonData.write(to: documentsPath.appendingPathComponent("logs.json"))
```

## 📚 API Reference

### LogRService Protocol

The main protocol that defines logging functionality:

```swift
@MainActor
public protocol LogRService: Observable {
    var recentLogs: [LogEntry] { get }
    var isCleanupRunning: Bool { get }
    
    // Core logging methods
    func log(level: LogLevel, message: String, category: LogCategory, file: String, function: String, line: Int) async
    func log(level: LogLevel, message: String, privateData: PrivateString, category: LogCategory, file: String, function: String, line: Int) async
    
    // Convenience methods (debug, info, notice, error, fault)
    // Query methods (getLogs, clearLogs, exportLogs)
}
```

### LogEntry Structure

```swift
public struct LogEntry: Sendable, Codable, Identifiable, Hashable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let category: LogCategory
    public let subsystem: String
    public let message: String
    public let file: String
    public let function: String
    public let line: Int
}
```

### LogLevel Enum

```swift
public enum LogLevel: String, CaseIterable, Sendable, Codable {
    case debug    // Detailed information for debugging
    case info     // General information messages
    case notice   // Significant events worth noting
    case error    // Error conditions that don't halt execution
    case fault    // Critical errors requiring immediate attention
}
```

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

## 📄 License

LogR is released under the MIT License. See [LICENSE](LICENSE) for details.

## 🙋 Support

- 📖 [Documentation](https://docs.logr.dev)
- 🐛 [Issue Tracker](https://github.com/yourorg/logr/issues)
- 💬 [Discussions](https://github.com/yourorg/logr/discussions)

---

Built with ❤️ for the Swift community