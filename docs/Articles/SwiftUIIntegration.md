---
layout: default
title: SwiftUI Integration
nav_order: 7
parent: Logr Documentation
---

# SwiftUI Integration

Learn how to integrate Logr with SwiftUI and use the powerful LogViewer component.

[← Back to Documentation](../index.md)

## Overview

Logr is designed with SwiftUI in mind, providing seamless integration through the environment system and a full-featured log viewer component.

## Environment Integration

### Setting Up the Logger

Use the `.logRService(_:)` modifier to inject the logger into the environment:

```swift
import SwiftUI
import Logr

@main
struct MyApp: App {
    let logger = try! LogR(storage: SQLiteStorage())

    var body: some Scene {
        WindowGroup {
            ContentView()
                .logRService(logger)
        }
    }
}
```

The logr service should always be set in the environment previously before calling any of the logging display views.

### Accessing the Logger

Access the logger through the environment:

```swift
import SwiftUI
import Logr

struct ContentView: View {
    @Environment(\.logService) private var logger

    var body: some View {
        Button("Test") {
            logger.info("Button tapped", category: .ui)
        }
    }
}
```

## LogViewer Component

The `LogViewer` provides a complete log viewing interface.

### Basic Usage


```swift
import SwiftUI
import LogrUI

struct LogsView: View {
    var body: some View {
        NavigationStack {
            LogViewer()
        }
    }
}
```



### In a Tab View

```swift
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

### In Settings

```swift
struct SettingsView: View {
    var body: some View {
        List {
            Section("Account") {
                // Account settings
            }

            Section("Developer") {
                NavigationLink {
                    LogViewer()
                } label: {
                    Label("View Logs", systemImage: "list.bullet.rectangle")
                }
            }
        }
        .navigationTitle("Settings")
    }
}
```

## LogViewer Features

### Filtering

The viewer includes comprehensive filtering:

- **By Level**: Filter by debug, info, notice, warning, error, fault
- **By Category**: Filter by specific categories (network, ui, etc.)
- **By Search**: Full-text search across messages and categories
- **By Date**: Automatic chronological ordering

**Usage:**
1. Tap the "Filters" button in the toolbar
2. Select desired levels and categories
3. Logs update in real-time

### Search

Full-text search across all logs:

```swift
// Search is built into LogViewer
LogViewer() // Includes search bar automatically
```

Search matches:
- Log messages
- Category names
- Category display names

### Export & Sharing

Export logs in multiple formats:

**From the Menu:**
1. Tap the ellipsis (•••) button
2. Select "Export & Share"
3. Choose format:
   - **JSON**: Structured data for processing
   - **CSV**: Spreadsheet-compatible
   - **TXT**: Human-readable text

**Programmatic Export:**
```swift
@Environment(\.logService) private var logger

func exportLogs() {
    if let jsonData = logger.exportLogs(format: .json) {
        // Save or share JSON data
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("logs.json")
        try? jsonData.write(to: url)
    }
}
```

### AI Analysis (iOS 26+)

When running on iOS 26+, the viewer shows AI analysis options:

- **Scan for Privacy Issues**: Detects sensitive data in logs
- **Summarize Issues**: Identifies patterns and critical errors

These options appear automatically in the menu when available.

### Expand/Collapse

Toggle between compact and detailed views:

- **Compact**: Shows timestamp, level, category, and truncated message
- **Expanded**: Shows full message, file, function, and line number

Use the "Expand All" / "Collapse All" button in the menu.

### Clear Logs

Clear all logs with confirmation:

1. Tap the ellipsis (•••) button
2. Select "Clear All Logs"
3. Confirm the action

## Custom Log Views

### Simple Log List

Create a minimal log viewer:

```swift
struct SimpleLogView: View {
    @Environment(\.logService) private var logger

    var body: some View {
        List(logger.recentLogs) { entry in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.level.visualQueue)
                    Text(entry.message)
                        .font(.body)
                }

                Text(entry.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Logs")
    }
}
```

### Filtered Log View

Show only specific logs:

```swift
struct ErrorLogView: View {
    @Environment(\.logService) private var logger

    private var errorLogs: [LogEntry] {
        logger.recentLogs.filter { entry in
            entry.level == .error || entry.level == .fault
        }
    }

    var body: some View {
        List(errorLogs) { entry in
            VStack(alignment: .leading) {
                Text(entry.message)
                    .font(.headline)

                Text("\(entry.file):\(entry.line)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Errors")
        .overlay {
            if errorLogs.isEmpty {
                ContentUnavailableView(
                    "No Errors",
                    systemImage: "checkmark.circle",
                    description: Text("All systems running smoothly")
                )
            }
        }
    }
}
```

### Category-Specific View

Show logs for a specific category:

```swift
struct NetworkLogView: View {
    @Environment(\.logService) private var logger

    private var networkLogs: [LogEntry] {
        logger.recentLogs.filter { entry in
            [.network, .api, .http, .websocket, .ssl].contains(entry.category)
        }
    }

    var body: some View {
        List(networkLogs) { entry in
            LogEntryRow(entry: entry)
        }
        .navigationTitle("Network Logs")
    }
}
```

### Real-Time Log Stream

Watch logs in real-time:

```swift
struct LogStreamView: View {
    @Environment(\.logService) private var logger
    @State private var scrollToBottom = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack {
                    ForEach(logger.recentLogs) { entry in
                        LogEntryRow(entry: entry)
                            .id(entry.id)
                    }
                }
            }
            .onChange(of: logger.recentLogs.count) { _, _ in
                // Auto-scroll to latest log
                if let lastLog = logger.recentLogs.first {
                    withAnimation {
                        proxy.scrollTo(lastLog.id, anchor: .bottom)
                    }
                }
            }
        }
        .navigationTitle("Live Logs")
    }
}
```

## Observable Updates

Logr uses `@Observable` for automatic SwiftUI updates:

```swift
@Observable
@MainActor
public final class LogR: LogRService {
    public private(set) var recentLogs: [LogEntry] = []

    // Adding a log automatically updates SwiftUI
    public func log(...) {
        let entry = LogEntry(...)
        recentLogs.insert(entry, at: 0) // SwiftUI updates automatically
    }
}
```

**Benefits:**
- No need for `@Published` or `ObservableObject`
- No manual `objectWillChange.send()` calls
- Efficient, fine-grained updates
- Automatic view invalidation

### Reactive Views

Views update automatically when logs change:

```swift
struct LogCountView: View {
    @Environment(\.logService) private var logger

    var body: some View {
        // Updates automatically when recentLogs changes
        Text("\(logger.recentLogs.count) logs")
    }
}
```

## Log Badges & Indicators

Show log counts in your UI:

```swift
struct TabViewWithBadge: View {
    @Environment(\.logService) private var logger

    private var errorCount: Int {
        logger.recentLogs.filter { $0.level == .error || $0.level == .fault }.count
    }

    var body: some View {
        TabView {
            ContentView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }

            LogViewer()
                .tabItem {
                    Label("Logs", systemImage: "list.bullet")
                }
                .badge(errorCount > 0 ? errorCount : nil)
        }
    }
}
```

## Debug Menu Integration

Add a debug menu to your app:

```swift
struct ContentView: View {
    @Environment(\.logService) private var logger
    @State private var showDebugMenu = false

    var body: some View {
        NavigationStack {
            // Your content

            Text("Main Content")
        }
        .toolbar {
            #if DEBUG
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showDebugMenu = true
                } label: {
                    Image(systemName: "ladybug")
                }
            }
            #endif
        }
        .sheet(isPresented: $showDebugMenu) {
            NavigationStack {
                DebugMenuView()
            }
        }
    }
}

struct DebugMenuView: View {
    @Environment(\.logService) private var logger
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("Logging") {
                NavigationLink("View Logs") {
                    LogViewer()
                }

                Button("Generate Test Logs") {
                    generateTestLogs()
                }

                Button("Clear All Logs") {
                    Task {
                        try await logger.clearLogs()
                    }
                }
            }

            Section("Statistics") {
                LabeledContent("Total Logs", value: "\(logger.recentLogs.count)")
                LabeledContent("Errors", value: "\(errorCount)")
                LabeledContent("Warnings", value: "\(warningCount)")
            }
        }
        .navigationTitle("Debug Menu")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    private var errorCount: Int {
        logger.recentLogs.filter { $0.level == .error || $0.level == .fault }.count
    }

    private var warningCount: Int {
        logger.recentLogs.filter { $0.level == .warning }.count
    }

    private func generateTestLogs() {
        logger.debug("Test debug log", category: .debug)
        logger.info("Test info log", category: .system)
        logger.warning("Test warning log", category: .system)
        logger.error("Test error log", category: .system)
    }
}
```

## Testing in SwiftUI Previews

Use `MockLogR` for previews:

```swift
#Preview {
    NavigationStack {
        LogViewer()
    }
    .environment(\.logService, MockLogR())
}

#Preview("Custom Mock") {
    let mock = MockLogR()

    // Add custom test logs
    mock.info("Test message", category: .network)
    mock.error("Test error", category: .database)

    return ContentView()
        .logRService(mock)
}
```

## Best Practices

### 1. Single Logger Instance

Create one logger instance per app:

```swift
@main
struct MyApp: App {
    // Single instance
    let logger = try! LogR(storage: SQLiteStorage())

    var body: some Scene {
        WindowGroup {
            ContentView()
                .logRService(logger)
        }
    }
}
```

### 2. Conditional Debug Menu

Only show log viewer in debug builds:

```swift
#if DEBUG
.toolbar {
    ToolbarItem {
        NavigationLink {
            LogViewer()
        } label: {
            Image(systemName: "list.bullet")
        }
    }
}
#endif
```

### 3. Protect Against Over-Logging in Views

Avoid logging in `body`:

```swift
// ❌ Bad - logs on every view update
var body: some View {
    logger.debug("View updated")
    return Text("Hello")
}

// ✅ Good - log in actions only
var body: some View {
    Text("Hello")
        .onAppear {
            logger.info("View appeared", category: .ui)
        }
}
```

### 4. Use Task for Async Operations

```swift
Button("Clear Logs") {
    Task {
        try await logger.clearLogs()
    }
}
```

## Summary

SwiftUI integration provides:

✅ **Environment-based** - Easy access throughout the app
✅ **Reactive** - Automatic updates with `@Observable`
✅ **Full-Featured Viewer** - Complete log management UI
✅ **Customizable** - Build your own log views
✅ **Debug-Friendly** - Perfect for development and testing

The `LogViewer` component gives you a production-ready log viewing interface with zero configuration required.

## Related Documentation

- [Getting Started](./GettingStarted.md) - Initial setup
- [Testing and Mocking](./TestingAndMocking.md) - Using MockLogR in previews
- [AI Analysis](./AIAnalysis.md) - AI features in LogViewer
