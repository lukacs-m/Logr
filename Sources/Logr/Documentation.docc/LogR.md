# ``LogR``

A powerful, persistent logging library for Apple platforms that leverages OSLog while providing persistent storage and SwiftUI visualization.

## Overview

LogR is a comprehensive logging solution that combines the power of Apple's OSLog framework with persistent storage capabilities. It provides:

- **Persistent Logging**: Unlike standard OSLog entries that are cleared between sessions, LogR maintains logs persistently
- **SwiftUI Integration**: Built-in log viewer with filtering, search, and export capabilities
- **Privacy-Aware**: Full support for Apple's privacy operators for sensitive data
- **Configurable**: Flexible configuration for log retention, levels, and cleanup
- **Swift 6.2 Compatible**: Built with the latest Swift concurrency and safety features

## Quick Start

### Basic Usage

```swift
import LogR

// Use the shared instance
await LogR.shared.info("Application started")
await LogR.shared.error("Failed to load user data")

// Or create your own instance
let logger = LogR()
await logger.debug("Debug information", category: "network")
```

### Privacy-Aware Logging

```swift
let userToken = PrivateString("abc123token", privacy: .sensitive)
await LogR.shared.info("User authenticated", privateData: userToken)
// Logs: "User authenticated <sensitive>" to persistent storage
// Logs: "User authenticated abc123token" to OSLog with proper privacy
```

### SwiftUI Integration

```swift
import SwiftUI
import LogR

struct ContentView: View {
    var body: some View {
        NavigationView {
            LogViewer()
        }
    }
}
```

## Topics

### Essentials

- ``LogR``
- ``LogEntry``
- ``LogLevel``
- ``LogrConfiguration``

### Privacy and Security

- ``PrivateString``
- ``PrivacyLevel``

### Storage

- ``PersistentStorage``
- ``FileSystemStorage``

### SwiftUI Components

- ``LogViewer``

### Configuration Management

- ``ConfigurationManager``
- ``ExportFormat``

## Installation

Add LogR to your Swift Package Manager dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/yourorg/logr", from: "1.0.0")
]
```

## Configuration

### Custom Configuration

```swift
let config = LogrConfiguration(
    maxLogEntries: 5000,
    maxLogAge: 24 * 60 * 60, // 1 day
    enabledLevels: [.info, .error, .fault],
    subsystem: "com.myapp.logging",
    cleanupInterval: 30 * 60 // 30 minutes
)

let logger = LogR(configuration: config)
```

### Custom Storage

```swift
class MyCustomStorage: PersistentStorage {
    // Implement your custom storage logic
    func store(_ entry: LogEntry) async throws {
        // Custom storage implementation
    }
    
    // ... other required methods
}

let logger = LogR(storage: MyCustomStorage())
```

## Export Options

LogR supports multiple export formats:

```swift
// Export as JSON
let jsonData = try await logger.exportLogs(format: .json)

// Export as CSV for spreadsheet analysis
let csvData = try await logger.exportLogs(format: .csv)

// Export as plain text for easy reading
let textData = try await logger.exportLogs(format: .txt)
```

## Best Practices

1. **Use appropriate log levels**: Reserve `.fault` for critical errors, `.error` for recoverable errors, and `.debug` for development information.

2. **Leverage categories**: Organize logs by feature or system component:
   ```swift
   await logger.info("Request completed", category: "networking")
   await logger.debug("UI updated", category: "interface")
   ```

3. **Handle sensitive data**: Always use `PrivateString` for sensitive information:
   ```swift
   let sensitiveData = PrivateString(userPassword, privacy: .sensitive)
   await logger.debug("Authentication attempt", privateData: sensitiveData)
   ```

4. **Configure cleanup appropriately**: Balance storage usage with log retention needs:
   ```swift
   let config = LogrConfiguration(
       maxLogEntries: 1000,  // Keep last 1000 entries
       maxLogAge: 7 * 24 * 60 * 60  // Keep logs for 7 days
   )
   ```

## Platform Support

- iOS 17.0+
- macOS 14.0+
- tvOS 17.0+
- watchOS 10.0+

## Thread Safety

LogR is built with Swift 6.2 and full concurrency support. All methods are actor-isolated and thread-safe. The `@Observable` conformance ensures SwiftUI updates happen on the main actor.

## Performance Considerations

- Log entries are stored asynchronously to avoid blocking the calling thread
- Automatic cleanup runs at configurable intervals to manage storage usage
- In-memory caching of recent logs for fast UI updates
- Efficient filtering and querying capabilities for large log sets