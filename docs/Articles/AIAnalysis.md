---
layout: default
title: AI Analysis
nav_order: 6
parent: Logr Documentation
---

# AI Analysis Features

Learn how to use Apple Intelligence to analyze logs for privacy issues and summarize critical problems.

[← Back to Documentation](../index.md)

## Overview

Logr integrates with Apple Intelligence (iOS 26+) to provide powerful AI-powered log analysis. These features help you identify privacy violations and understand patterns in your logs automatically.

## Availability

AI analysis features require:
- iOS 26.0+ or macOS 26.0+ or tvOS 26.0+ or watchOS 12.0+
- Apple Intelligence enabled on the device
- The on-device Foundation model must be ready — `AIAnalyzer.isAvailable` is `false` (and analysis throws `AIAnalyzerError.modelUnavailable`) while the device is not eligible, Apple Intelligence is disabled, or the model assets are not ready. Logr itself makes no network requests.

## Setup

### Enable AI Analysis

```swift
import Logr

if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *) {
    let analyzer = AIAnalyzer()
    let logger = try LogR(
        storage: SQLiteStorage(),
        logAnalyser: analyzer
    )

    // Check if available (`canAnalyseLogs` is @MainActor)
    Task { @MainActor in
        if logger.canAnalyseLogs {
            print("AI analysis available")
        }
    }
}
```

### Tuning the Analyzer

```swift
let analyzer = AIAnalyzer(configuration: AnalyzerConfiguration(
    maxLogsPerRequest: 20,          // logs per model request (context is limited)
    enableParallelProcessing: true, // analyse chunks concurrently
    maxConcurrentChunks: 3,         // clamped to 1...8
    prewarmModel: true))
```

Results from multiple chunks are merged; issues with the same category and title are
combined with summed `occurrences`, sorted by severity.

### Check Availability at Runtime

```swift
@Environment(\.logService) private var logger

var body: some View {
    VStack {
        if #available(iOS 26.0, *), logger.canAnalyseLogs {
            Button("Scan for Privacy Issues") {
                Task {
                    try await scanLogs()
                }
            }
        } else {
            Text("AI analysis not available")
                .foregroundStyle(.secondary)
        }
    }
}
```

## Privacy Scanning

Detect potential privacy violations and sensitive data exposure in your logs.

### What It Detects

- **Personally Identifiable Information (PII)**
  - Names
  - Email addresses
  - Phone numbers
  - Physical addresses

- **Credentials & Secrets**
  - Passwords
  - API keys
  - Access tokens
  - Session IDs

- **Financial Information**
  - Credit card numbers
  - Bank account numbers
  - Transaction IDs

- **Health Information**
  - Medical record numbers
  - Health conditions
  - Treatment information

- **Other Sensitive Data**
  - IP addresses
  - Device identifiers
  - Location data

### Using Privacy Scanning

```swift
import Logr

if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *) {
    Task { @MainActor in
        do {
            let result = try await logger.scanForPrivacyIssues()

            print(result.summary)
            print("Critical: \(result.criticalCount), high: \(result.highCount)")

            for warning in result.warnings {
                print("\n⚠️ [\(warning.severity)] \(warning.exposureType) at \(warning.file):\(warning.line)")
                print("   \(warning.explanation)")
                print("   Recommendation: \(warning.recommendation)")
            }
        } catch {
            print("Privacy scan failed: \(error)")
        }
    }
}
```

### Privacy Analysis Result

The `PrivacyAnalysisResult` contains:

```swift
public struct PrivacyAnalysisResult: Sendable, Equatable {
    /// Individual warnings found
    public var warnings: [PrivacyWarning]

    /// Summary of the analysis
    public var summary: String

    /// Number of critical / high severity warnings
    public var criticalCount: Int
    public var highCount: Int

    public var isEmpty: Bool { get }
    public static var empty: PrivacyAnalysisResult { get }
}
```

### Privacy Warning Details

Each `PrivacyWarning` includes:

```swift
public struct PrivacyWarning: Sendable, Identifiable, Hashable {
    /// Where the exposure was logged
    public var file: String
    public var line: Int

    /// Kind of exposure, e.g. "email", "credit card", "API key"
    public var exposureType: String

    /// What was exposed (the model is instructed to return "[REDACTED]")
    public var exposedContent: String

    /// Why this is a problem
    public var explanation: String

    /// Severity level
    public var severity: LogSeverity // .critical, .high, .medium, .low

    /// Specific recommendation to address the issue
    public var recommendation: String
}
```

### Example Output

```
Found 3 potential privacy exposures: 1 critical, 1 high severity.
Critical: 1, high: 1

⚠️ [critical] API key at NetworkClient.swift:88
   A bearer token is written to the log in plain text.
   Recommendation: Remove the token, or log token.redacted(keeping: 4, position: .end)

⚠️ [high] email at LoginViewController.swift:42
   An email address identifies the user directly.
   Recommendation: Log a user ID, or userEmail.redactedEmail()

⚠️ [medium] IP address at SessionManager.swift:120
   Client IPs are personal data under GDPR.
   Recommendation: Anonymize with ip.redactedIP() before logging
```

## Issue Summarization

Get AI-powered summaries of critical issues, errors, and patterns in your logs.

### What It Analyzes

- **Error Patterns**: Identifies recurring errors and their root causes
- **System Issues**: Detects system-level problems (memory, performance, etc.)
- **Critical Failures**: Highlights faults that need immediate attention
- **Trends**: Identifies increasing error rates or degrading performance
- **Affected Areas**: Categorizes issues by system component

### Using Issue Summarization

```swift
if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *) {
    Task { @MainActor in
        do {
            let summary = try await logger.summarizeIssues()

            print(summary.executiveSummary)
            print("Errors: \(summary.totalErrors), warnings: \(summary.totalWarnings), faults: \(summary.totalFaults)")

            print("\nIssues:")
            for issue in summary.issues {
                print("- [\(issue.severity)] \(issue.title) (\(issue.file):\(issue.line), ×\(issue.occurrences))")
                print("  Fix: \(issue.suggestedFix)")
            }

            print("\nPatterns:")
            for pattern in summary.patterns {
                print("- \(pattern)")
            }

            print("\nPriority Actions:")
            for action in summary.priorityActions {
                print("- \(action)")
            }
        } catch {
            print("Issue summarization failed: \(error)")
        }
    }
}
```

### Log Issue Summary

The `LogIssueSummary` contains:

```swift
public struct LogIssueSummary: Sendable, Equatable {
    /// Overall summary of the log analysis
    public var executiveSummary: String

    /// Individual issues identified
    public var issues: [LogIssue]

    /// Totals by level
    public var totalErrors: Int
    public var totalWarnings: Int
    public var totalFaults: Int

    /// Recurring patterns and what to do first
    public var patterns: [String]
    public var priorityActions: [String]

    public var isEmpty: Bool { get }
}

public struct LogIssue: Sendable, Identifiable, Hashable {
    public var category: String       // "error", "warning", "crash", "performance", "other"
    public var title: String
    public var description: String
    public var file: String
    public var line: Int
    public var occurrences: Int
    public var severity: LogSeverity
    public var suggestedFix: String
}
```

### Example Output

```
Analyzed 45 errors, 23 warnings, and 3 faults. Found 12 distinct issues:
2 critical, 4 high severity. Immediate action required on critical issues.
Errors: 45, warnings: 23, faults: 3

Issues:
- [critical] Force unwrap causing crashes (DataParser.swift:89, ×5)
  Fix: Use optional binding instead of force unwrapping
- [high] Network timeout in API requests (NetworkManager.swift:156, ×23)
  Fix: Implement retry with exponential backoff

Patterns:
- Error rate spikes during peak usage hours
- Network issues cluster around the same endpoints

Priority Actions:
- Fix the force unwrap in DataParser.swift:89
- Add retry handling to NetworkManager
```

## In SwiftUI (LogViewer)

The `LogViewer` automatically integrates AI features when available:

```swift
import LogrUI

NavigationStack {
    LogViewer() // the "Analyze logs" submenu appears automatically on iOS 26+
}
```

The viewer shows:
- An **Analyze logs** submenu with **Scan for Privacy Issues** and **Summarize Issues** (only when `canAnalyseLogs` is true)
- Results in dedicated sheets (`PrivacyWarningsView`, `IssueSummaryView`) with a ReScan button
- A progress view while an analysis is running

Hide the group with `LogViewer(functionalityFilter: [.sharing, .statistics])`.
`AIAnalysisView()` (iOS 26+) is also available standalone inside your own `NavigationStack`.

## Tracking Progress

`analysisProgress` (`@MainActor`) is set when a scan starts, updated as each chunk
completes, and cleared when the scan ends. The latest results stay on the service as
`privacyAnalysisResult` / `logIssueSummary`, so a view can render them directly — both
scan methods are `@discardableResult`.

```swift
if let progress = logger.analysisProgress, !progress.isComplete {
    ProgressView(value: progress.progress) {
        Text("Analyzed \(progress.analyzedLogs) of \(progress.totalLogs) (\(progress.percentComplete)%)")
    }
}
```

Calling an analyzer directly also accepts a progress callback (invoked on the main actor):

```swift
let result = try await analyzer.scanForPrivacyIssues(logs: logs) { progress in
    print("\(progress.percentComplete)%")
}
```

## Custom AI Analyzer

Implement your own AI analyzer using a different service:

```swift
@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
struct CustomAIAnalyzer: LogAIAnalyzer {   // `LogAIAnalyzer` is Sendable: use a struct or an actor
    var isAvailable: Bool { MyAIService.isConfigured }

    func scanForPrivacyIssues(logs: [LogEntry]) async throws -> PrivacyAnalysisResult {
        try await scanForPrivacyIssues(logs: logs, onProgress: { _ in })
    }

    func scanForPrivacyIssues(logs: [LogEntry],
                              onProgress: @escaping @MainActor @Sendable (AnalysisProgress) -> Void)
        async throws -> PrivacyAnalysisResult {
        await onProgress(.starting(totalLogs: logs.count))
        let response = try await MyAIService.analyzePrivacy(logs: logs)

        // Convert to Logr format
        let warnings = response.findings.map { finding in
            PrivacyWarning(file: finding.file,
                           line: finding.line,
                           exposureType: finding.kind,
                           exposedContent: "[REDACTED]",
                           explanation: finding.why,
                           severity: mapSeverity(finding.level),
                           recommendation: finding.fix)
        }
        await onProgress(AnalysisProgress(totalLogs: logs.count, analyzedLogs: logs.count))
        return PrivacyAnalysisResult(warnings: warnings,
                                     summary: response.summary,
                                     criticalCount: warnings.count { $0.severity == .critical },
                                     highCount: warnings.count { $0.severity == .high })
    }

    func summarizeIssues(logs: [LogEntry]) async throws -> LogIssueSummary {
        try await summarizeIssues(logs: logs, onProgress: { _ in })
    }

    func summarizeIssues(logs: [LogEntry],
                         onProgress: @escaping @MainActor @Sendable (AnalysisProgress) -> Void)
        async throws -> LogIssueSummary {
        let response = try await MyAIService.summarizeIssues(logs: logs)

        return LogIssueSummary(executiveSummary: response.summary,
                               issues: response.issues.map { issue in
                                   LogIssue(category: issue.kind,
                                            title: issue.title,
                                            description: issue.detail,
                                            file: issue.file,
                                            line: issue.line,
                                            occurrences: issue.count,
                                            severity: mapSeverity(issue.level),
                                            suggestedFix: issue.fix)
                               },
                               totalErrors: logs.count { $0.level == .error },
                               totalWarnings: logs.count { $0.level == .warning },
                               totalFaults: logs.count { $0.level == .fault },
                               patterns: response.patterns,
                               priorityActions: response.actions)
    }
}

// Use it
if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *) {
    let customAnalyzer = CustomAIAnalyzer()
    let logger = try LogR(logAnalyser: customAnalyzer)
}
```

## Best Practices

### 1. Run Analysis Periodically

```swift
// Schedule daily privacy scan
@MainActor
func scheduleDailyPrivacyScan() {
    guard #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *) else { return }

    Task { @MainActor in
        while true {
            // Wait 24 hours
            try await Task.sleep(for: .seconds(24 * 60 * 60))

            // Run scan
            if logger.canAnalyseLogs {
                let result = try await logger.scanForPrivacyIssues()

                // Alert if anything serious was found
                if result.criticalCount > 0 || result.highCount > 0 {
                    await showPrivacyAlert(result)
                }
            }
        }
    }
}
```

### 2. Act on Warnings

```swift
func handlePrivacyWarnings(_ result: PrivacyAnalysisResult) async {
    for warning in result.warnings where warning.severity == .critical {
        // Critical issues - log to monitoring service
        await monitoringService.logCriticalPrivacyIssue(warning)

        // Notify team
        await notificationService.send(
            title: "Critical Privacy Issue",
            message: "\(warning.exposureType) at \(warning.file):\(warning.line) — \(warning.explanation)"
        )

        // If API keys exposed, rotate them immediately
        if warning.exposureType.localizedCaseInsensitiveContains("key") ||
           warning.exposureType.localizedCaseInsensitiveContains("token") {
            await securityService.rotateAPIKeys()
        }
    }
}
```

### 3. Integrate with Development Workflow

```swift
#if DEBUG
@MainActor
func runPreReleaseChecks() async throws {
    guard #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *) else { return }

    // Privacy scan
    let privacyResult = try await logger.scanForPrivacyIssues()

    // Fail if anything critical was exposed
    guard privacyResult.criticalCount == 0 else {
        throw BuildError.privacyCheckFailed(privacyResult)
    }

    // Issue summary
    let issueSummary = try await logger.summarizeIssues()

    // Fail if critical issues were found
    let hasCriticalIssues = issueSummary.issues.contains { $0.severity == .critical }

    guard !hasCriticalIssues else {
        throw BuildError.criticalIssuesFound(issueSummary)
    }

    print("✅ Pre-release checks passed")
}
#endif
```

### 4. Log Analysis Results

```swift
func logAnalysisResults(_ result: PrivacyAnalysisResult) {
    // Don't log to Logr (would create recursion)
    // Use system logging instead
    let osLog = OSLog(subsystem: "com.myapp", category: "privacy-analysis")

    os_log(.info, log: osLog, "Critical: %d, high: %d", result.criticalCount, result.highCount)
    os_log(.info, log: osLog, "Warnings: %d", result.warnings.count)

    // Store in analytics
    analytics.track("privacy_scan_completed", properties: [
        "critical": result.criticalCount,
        "high": result.highCount,
        "warnings": result.warnings.count
    ])
}
```

## Error Handling

```swift
do {
    let result = try await logger.scanForPrivacyIssues()
    // Handle result
} catch AIAnalyzerError.missingAnalyzer {
    print("LogR was created without logAnalyser:")
} catch AIAnalyzerError.modelUnavailable(let reason) {
    print("Apple Intelligence not available: \(reason)")
} catch AIAnalyzerError.noLogsToAnalyze {
    print("Nothing to analyze")   // thrown by a direct analyzer call with an empty array
} catch AIAnalyzerError.contextLengthExceeded, AIAnalyzerError.inferenceTimeout {
    print("Lower AnalyzerConfiguration.maxLogsPerRequest or analyse fewer logs")
} catch AIAnalyzerError.invalidResponse, AIAnalyzerError.mergeError {
    print("The model produced output Logr could not decode — retry")
} catch {
    print("Unexpected error: \(error)")
}
```

## Performance Considerations

### Optimize Performance

```swift
// Analyze recent logs only (`recentLogs` is @MainActor through the protocol)
@MainActor
func analyzeRecentLogs() async throws {
    guard #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *) else { return }

    // Get logs from last hour only
    let oneHourAgo = Date().addingTimeInterval(-3600)
    let recentLogs = logger.recentLogs.filter { $0.timestamp > oneHourAgo }

    // Only proceed if we have logs to analyze
    guard !recentLogs.isEmpty else { return }

    // Run analysis on subset
    let analyzer = AIAnalyzer()
    let result = try await analyzer.scanForPrivacyIssues(logs: recentLogs)

    // Handle result
}
```

## Summary

AI analysis features provide:

✅ **Privacy Protection** - Detect sensitive data in logs before it becomes a problem
✅ **Issue Detection** - Identify patterns and critical errors automatically
✅ **Actionable Insights** - Get specific recommendations for improvements
✅ **SwiftUI Integration** - Built-in UI in LogViewer
✅ **Extensible** - Implement custom analyzers for other AI services

Use AI analysis to maintain log hygiene, protect user privacy, and quickly identify critical issues in your application.

## Related Documentation

- [Privacy and Security](./PrivacyAndSecurity.md) - Privacy best practices
- [SwiftUI Integration](./SwiftUIIntegration.md) - LogViewer with AI features
- [Getting Started](./GettingStarted.md) - Basic setup
