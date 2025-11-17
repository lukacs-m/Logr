//import Foundation
//import Testing
//@testable import Logr
//
//@Suite("AI Analyzer Tests")
////@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 13.0, *)
//struct AIAnalyzerTests {
//    // MARK: - Mock Analyzer for Testing
//
//    actor MockLogAIAnalyzer: LogAIAnalyzer {
//        var mockIsAvailable: Bool = true
//        var mockPrivacyResult: PrivacyAnalysisResult?
//        var mockIssueSummary: LogIssueSummary?
//        var shouldThrowError: AIAnalyzerError?
//
//        var isAvailable: Bool {
//            get async { mockIsAvailable }
//        }
//
//        func scanForPrivacyIssues(logs: [LogEntry]) async throws -> PrivacyAnalysisResult {
//            if let error = shouldThrowError {
//                throw error
//            }
//            if let result = mockPrivacyResult {
//                return result
//            }
//            return PrivacyAnalysisResult(warnings: [], summary: "No issues", criticalCount: 0, highCount: 0)
//        }
//
//        func summarizeIssues(logs: [LogEntry]) async throws -> LogIssueSummary {
//            if let error = shouldThrowError {
//                throw error
//            }
//            if let summary = mockIssueSummary {
//                return summary
//            }
//            return LogIssueSummary(
//                executiveSummary: "All clear",
//                issues: [],
//                totalErrors: 0,
//                totalWarnings: 0,
//                totalFaults: 0,
//                patterns: [],
//                priorityActions: []
//            )
//        }
//    }
//
//    // MARK: - Test Data
//
//    let sampleLogs = [
//        LogEntry(
//            level: .error,
//            category: .system,
//            subsystem: "com.test.app",
//            message: "User email: test@example.com failed",
//            file: "TestFile.swift",
//            line: 42
//        ),
//        LogEntry(
//            level: .fault,
//            category: .network,
//            subsystem: "com.test.app",
//            message: "Network timeout",
//            file: "NetworkManager.swift",
//            line: 156
//        ),
//        LogEntry(
//            level: .notice,
//            category: .ui,
//            subsystem: "com.test.app",
//            message: "Deprecated API usage",
//            file: "ViewController.swift",
//            line: 89
//        )
//    ]
//
//    // MARK: - Availability Tests
//
//    @Test("Analyzer reports availability correctly")
//    func testAvailability() async {
//        let analyzer = MockLogAIAnalyzer()
//        analyzer.mockIsAvailable = true
//
//        let available = await analyzer.isAvailable
//        #expect(available == true)
//    }
//
//    @Test("Analyzer reports unavailability correctly")
//    func testUnavailability() async {
//        let analyzer = MockLogAIAnalyzer()
//        analyzer.mockIsAvailable = false
//
//        let available = await analyzer.isAvailable
//        #expect(available == false)
//    }
//
//    // MARK: - Privacy Scanning Tests
//
//    @Test("Privacy scan returns empty result for clean logs")
//    func testPrivacyScanCleanLogs() async throws {
//        let analyzer = MockLogAIAnalyzer()
//        analyzer.mockPrivacyResult = PrivacyAnalysisResult(
//            warnings: [],
//            summary: "No privacy concerns detected",
//            criticalCount: 0,
//            highCount: 0
//        )
//
//        let result = try await analyzer.scanForPrivacyIssues(logs: sampleLogs)
//
//        #expect(result.warnings.isEmpty)
//        #expect(result.criticalCount == 0)
//        #expect(result.highCount == 0)
//    }
//
//    @Test("Privacy scan detects email exposure")
//    func testPrivacyScanDetectsEmail() async throws {
//        let analyzer = MockLogAIAnalyzer()
//        let emailWarning = PrivacyWarning(
//            file: "TestFile.swift",
//            line: 42,
//            exposureType: "email",
//            exposedContent: "test@example.com",
//            explanation: "Email address exposed in logs",
//            severity: "high",
//            recommendation: "Redact email addresses"
//        )
//        analyzer.mockPrivacyResult = PrivacyAnalysisResult(
//            warnings: [emailWarning],
//            summary: "Found 1 privacy issue",
//            criticalCount: 0,
//            highCount: 1
//        )
//
//        let result = try await analyzer.scanForPrivacyIssues(logs: sampleLogs)
//
//        #expect(result.warnings.count == 1)
//        #expect(result.warnings.first?.exposureType == "email")
//        #expect(result.highCount == 1)
//    }
//
//    @Test("Privacy scan throws error for empty logs")
//    func testPrivacyScanEmptyLogs() async {
//        let analyzer = MockLogAIAnalyzer()
//        analyzer.shouldThrowError = .noLogsToAnalyze
//
//        do {
//            _ = try await analyzer.scanForPrivacyIssues(logs: [])
//            #expect(Bool(false), "Should have thrown error")
//        } catch let error as AIAnalyzerError {
//            #expect(error == .noLogsToAnalyze)
//        } catch {
//            #expect(Bool(false), "Wrong error type")
//        }
//    }
//
//    @Test("Privacy scan throws error when model unavailable")
//    func testPrivacyScanModelUnavailable() async {
//        let analyzer = MockLogAIAnalyzer()
//        analyzer.shouldThrowError = .modelUnavailable
//
//        do {
//            _ = try await analyzer.scanForPrivacyIssues(logs: sampleLogs)
//            #expect(Bool(false), "Should have thrown error")
//        } catch let error as AIAnalyzerError {
//            #expect(error == .modelUnavailable)
//        } catch {
//            #expect(Bool(false), "Wrong error type")
//        }
//    }
//
//    // MARK: - Issue Summary Tests
//
//    @Test("Issue summary returns clean result for no issues")
//    func testIssueSummaryNoIssues() async throws {
//        let analyzer = MockLogAIAnalyzer()
//        analyzer.mockIssueSummary = LogIssueSummary(
//            executiveSummary: "No issues detected",
//            issues: [],
//            totalErrors: 0,
//            totalWarnings: 0,
//            totalFaults: 0,
//            patterns: [],
//            priorityActions: []
//        )
//
//        let summary = try await analyzer.summarizeIssues(logs: sampleLogs)
//
//        #expect(summary.issues.isEmpty)
//        #expect(summary.totalErrors == 0)
//        #expect(summary.totalWarnings == 0)
//        #expect(summary.totalFaults == 0)
//    }
//
//    @Test("Issue summary identifies error patterns")
//    func testIssueSummaryIdentifiesErrors() async throws {
//        let analyzer = MockLogAIAnalyzer()
//        let issue = LogIssue(
//            category: "error",
//            title: "Network timeout",
//            description: "Requests timing out",
//            file: "NetworkManager.swift",
//            line: 156,
//            occurrences: 5,
//            severity: "high",
//            suggestedFix: "Implement retry logic"
//        )
//        analyzer.mockIssueSummary = LogIssueSummary(
//            executiveSummary: "Found 1 high severity issue",
//            issues: [issue],
//            totalErrors: 5,
//            totalWarnings: 0,
//            totalFaults: 0,
//            patterns: ["Network errors during peak hours"],
//            priorityActions: ["Fix network timeout (NetworkManager.swift:156)"]
//        )
//
//        let summary = try await analyzer.summarizeIssues(logs: sampleLogs)
//
//        #expect(summary.issues.count == 1)
//        #expect(summary.issues.first?.category == "error")
//        #expect(summary.totalErrors == 5)
//        #expect(!summary.patterns.isEmpty)
//        #expect(!summary.priorityActions.isEmpty)
//    }
//
//    @Test("Issue summary throws error for empty logs")
//    func testIssueSummaryEmptyLogs() async {
//        let analyzer = MockLogAIAnalyzer()
//        analyzer.shouldThrowError = .noLogsToAnalyze
//
//        do {
//            _ = try await analyzer.summarizeIssues(logs: [])
//            #expect(Bool(false), "Should have thrown error")
//        } catch let error as AIAnalyzerError {
//            #expect(error == .noLogsToAnalyze)
//        } catch {
//            #expect(Bool(false), "Wrong error type")
//        }
//    }
//
//    // MARK: - Model Structure Tests
//
//    @Test("PrivacyWarning has correct identifiable")
//    func testPrivacyWarningIdentifiable() {
//        let warning = PrivacyWarning(
//            file: "Test.swift",
//            line: 10,
//            exposureType: "email",
//            exposedContent: "test@test.com",
//            explanation: "Test",
//            severity: "high",
//            recommendation: "Fix it"
//        )
//
//        #expect(warning.id == "Test.swift:10:email")
//    }
//
//    @Test("LogIssue has correct identifiable")
//    func testLogIssueIdentifiable() {
//        let issue = LogIssue(
//            category: "error",
//            title: "Test Error",
//            description: "Description",
//            file: "Test.swift",
//            line: 20,
//            occurrences: 1,
//            severity: "high",
//            suggestedFix: "Fix"
//        )
//
//        #expect(issue.id == "error:Test.swift:20")
//    }
//
//    @Test("AIAnalyzerError has proper descriptions")
//    func testAIAnalyzerErrorDescriptions() {
//        let errors: [AIAnalyzerError] = [
//            .modelUnavailable,
//            .contextLengthExceeded,
//            .inferenceTimeout,
//            .invalidResponse,
//            .noLogsToAnalyze
//        ]
//
//        for error in errors {
//            #expect(error.errorDescription != nil)
//            #expect(!error.errorDescription!.isEmpty)
//        }
//    }
//}
//
//// MARK: - AIAnalyzerError Equatable for Testing
//
//extension AIAnalyzerError: Equatable {
//    public static func == (lhs: AIAnalyzerError, rhs: AIAnalyzerError) -> Bool {
//        switch (lhs, rhs) {
//        case (.modelUnavailable, .modelUnavailable),
//             (.contextLengthExceeded, .contextLengthExceeded),
//             (.inferenceTimeout, .inferenceTimeout),
//             (.invalidResponse, .invalidResponse),
//             (.noLogsToAnalyze, .noLogsToAnalyze):
//            return true
//        case (.systemError, .systemError):
//            return true
//        default:
//            return false
//        }
//    }
//}
