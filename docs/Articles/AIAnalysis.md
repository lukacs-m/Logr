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
- Network connectivity for initial model download (cached afterward)

## Setup

### Enable AI Analysis

```swift
import Logr

if #available(iOS 26.0, *) {
    let analyzer = AIAnalyzer()
    let logger = LogR(
        storage: SQLiteStorage(),
        logAnalyser: analyzer
    )

    // Check if available
    if logger.canAnalyseLogs {
        print("AI analysis available")
    }
}
```

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

if #available(iOS 26.0, *) {
    Task {
        do {
            let result = try await logger.scanForPrivacyIssues()

            print("Privacy Score: \(result.privacyScore)/100")
            print("Warnings: \(result.warnings.count)")

            for warning in result.warnings {
                print("\n⚠️ \(warning.severity): \(warning.message)")
                print("   Recommendation: \(warning.recommendation)")

                if let affectedLogs = warning.affectedLogIDs {
                    print("   Affected logs: \(affectedLogs.count)")
                }
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
public struct PrivacyAnalysisResult {
    /// Overall privacy score (0-100, higher is better)
    public let privacyScore: Int

    /// List of privacy warnings found
    public let warnings: [PrivacyWarning]

    /// General recommendations
    public let recommendations: [String]

    /// Summary of the analysis
    public let summary: String
}
```

### Privacy Warning Details

Each `PrivacyWarning` includes:

```swift
public struct PrivacyWarning {
    /// Severity level
    public let severity: PrivacySeverity // .low, .medium, .high, .critical

    /// Human-readable warning message
    public let message: String

    /// Specific recommendation to address the issue
    public let recommendation: String

    /// IDs of logs that triggered this warning
    public let affectedLogIDs: [String]?

    /// Category of privacy issue
    public let category: String
}
```

### Example Output

```
Privacy Score: 45/100

⚠️ HIGH: Email addresses detected in logs
   Recommendation: Use user IDs instead of email addresses in log messages
   Affected logs: 12

⚠️ CRITICAL: API key exposed in debug logs
   Recommendation: Remove all API keys from log messages immediately
   Affected logs: 3

⚠️ MEDIUM: IP addresses logged without anonymization
   Recommendation: Anonymize or hash IP addresses before logging
   Affected logs: 47

Recommendations:
- Implement log scrubbing for sensitive data
- Use redacted string interpolation for user data
- Review all debug and info level logs for PII
- Consider using log categories to identify sensitive operations
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
if #available(iOS 26.0, *) {
    Task {
        do {
            let summary = try await logger.summarizeIssues()

            print("Summary: \(summary.summary)")

            print("\nKey Issues:")
            for issue in summary.keyIssues {
                print("- \(issue)")
            }

            print("\nRecommendations:")
            for recommendation in summary.recommendations {
                print("- \(recommendation)")
            }

            print("\nAffected Categories:")
            for category in summary.affectedCategories {
                print("- \(category)")
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
public struct LogIssueSummary {
    /// Overall summary of the log analysis
    public let summary: String

    /// Key issues identified
    public let keyIssues: [String]

    /// Actionable recommendations
    public let recommendations: [String]

    /// Categories affected by issues
    public let affectedCategories: [String]

    /// Timestamp of analysis
    public let analyzedAt: Date
}
```

### Example Output

```
Summary: Analysis of 5,234 logs reveals 3 critical areas requiring attention:
network connectivity issues causing 45% of errors, database connection pool
exhaustion during peak times, and memory pressure leading to app terminations.

Key Issues:
- Network timeout errors increased 300% in last 24 hours (network, api categories)
- Database connection pool exhausted 12 times during peak hours
- Out of memory warnings preceding 8 app crashes
- SSL certificate validation failing for 3rd party API
- Location permission denied causing 156 feature failures

Recommendations:
- Implement exponential backoff for network retries
- Increase database connection pool size or implement connection reuse
- Profile memory usage during peak times, consider releasing caches
- Update SSL certificate pinning configuration
- Add graceful degradation when location permission is denied
- Monitor error rates with alerting thresholds

Affected Categories:
- network (45% of errors)
- database (30% of errors)
- memory (15% of errors)
- location (8% of errors)
- ssl (2% of errors)
```

## In SwiftUI (LogViewer)

The `LogViewer` automatically integrates AI features when available:

```swift
import LogrUI

NavigationStack {
    LogViewer() // AI buttons appear automatically on iOS 26+
}
```

The viewer shows:
- **"Scan for Privacy Issues"** button in the menu
- **"Summarize Issues"** button in the menu
- Privacy analysis results in a dedicated view
- Issue summary in a dedicated view

## Custom AI Analyzer

Implement your own AI analyzer using a different service:

```swift
@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
class CustomAIAnalyzer: LogAIAnalyzer {
    nonisolated var isAvailable: Bool {
        // Check if your AI service is available
        return MyAIService.isConfigured
    }

    func scanForPrivacyIssues(logs: [LogEntry]) async throws -> PrivacyAnalysisResult {
        // Send logs to your AI service
        let response = try await MyAIService.analyzePrivacy(logs: logs)

        // Convert to Logr format
        return PrivacyAnalysisResult(
            privacyScore: response.score,
            warnings: response.warnings.map { warning in
                PrivacyWarning(
                    severity: mapSeverity(warning.level),
                    message: warning.message,
                    recommendation: warning.fix,
                    affectedLogIDs: warning.logIDs,
                    category: warning.type
                )
            },
            recommendations: response.recommendations,
            summary: response.summary
        )
    }

    func summarizeIssues(logs: [LogEntry]) async throws -> LogIssueSummary {
        let response = try await MyAIService.summarizeIssues(logs: logs)

        return LogIssueSummary(
            summary: response.summary,
            keyIssues: response.issues,
            recommendations: response.recommendations,
            affectedCategories: response.categories,
            analyzedAt: Date()
        )
    }
}

// Use it
if #available(iOS 26.0, *) {
    let customAnalyzer = CustomAIAnalyzer()
    let logger = LogR(logAnalyser: customAnalyzer)
}
```

## Best Practices

### 1. Run Analysis Periodically

```swift
// Schedule daily privacy scan
func scheduleDailyPrivacyScan() {
    guard #available(iOS 26.0, *) else { return }

    Task {
        while true {
            // Wait 24 hours
            try await Task.sleep(for: .seconds(24 * 60 * 60))

            // Run scan
            if logger.canAnalyseLogs {
                let result = try await logger.scanForPrivacyIssues()

                // Alert if score is low
                if result.privacyScore < 70 {
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
            message: warning.message
        )

        // If API keys exposed, rotate them immediately
        if warning.category == "credentials" {
            await securityService.rotateAPIKeys()
        }
    }
}
```

### 3. Integrate with Development Workflow

```swift
#if DEBUG
func runPreReleaseChecks() async throws {
    guard #available(iOS 26.0, *) else { return }

    // Privacy scan
    let privacyResult = try await logger.scanForPrivacyIssues()

    // Fail build if privacy score is too low
    guard privacyResult.privacyScore >= 80 else {
        throw BuildError.privacyCheckFailed(privacyResult)
    }

    // Issue summary
    let issueSummary = try await logger.summarizeIssues()

    // Fail build if critical issues found
    let hasCriticalIssues = issueSummary.keyIssues.contains { issue in
        issue.localizedCaseInsensitiveContains("critical") ||
        issue.localizedCaseInsensitiveContains("fault")
    }

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

    os_log(.info, log: osLog, "Privacy score: %d", result.privacyScore)
    os_log(.info, log: osLog, "Warnings: %d", result.warnings.count)

    // Store in analytics
    analytics.track("privacy_scan_completed", properties: [
        "score": result.privacyScore,
        "warnings": result.warnings.count,
        "critical_warnings": result.warnings.filter { $0.severity == .critical }.count
    ])
}
```

## Error Handling

```swift
do {
    let result = try await logger.scanForPrivacyIssues()
    // Handle result
} catch AIAnalyzerError.notAvailable {
    print("Apple Intelligence not available")
} catch AIAnalyzerError.analysisNotSupported {
    print("Analysis not supported on this device")
} catch AIAnalyzerError.networkError {
    print("Network error during analysis")
} catch AIAnalyzerError.modelDownloadFailed {
    print("Failed to download AI model")
} catch {
    print("Unexpected error: \(error)")
}
```

## Performance Considerations

### Optimize Performance

```swift
// Analyze recent logs only
func analyzeRecentLogs() async throws {
    guard #available(iOS 26.0, *) else { return }

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

- [Privacy and Security](../docs/Articles/PrivacyAndSecurity.md) - Privacy best practices
- [SwiftUI Integration](../docs/Articles/SwiftUIIntegration.md) - LogViewer with AI features
- [Getting Started](../docs/Articles/GettingStarted.md) - Basic setup
