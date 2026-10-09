#if LOGR_SYSTEM_MODEL
import Testing
@testable import Logr

@Suite("AIAnalyzer result merging")
struct AIAnalyzerMergeTests {
    @available(iOS 26.0, macOS 26.0, *)
    @Test("A warning reported by several chunks is listed and counted once")
    func privacyWarningsAreDeduplicated() async {
        let warning = PrivacyWarning(file: "Auth.swift",
                                     line: 42,
                                     exposureType: "email",
                                     exposedContent: "user@example.com",
                                     explanation: "Email logged on every login",
                                     severity: .critical,
                                     recommendation: "Redact the email")
        let chunk = PrivacyAnalysisResult(warnings: [warning], summary: "", criticalCount: 1, highCount: 0)

        let merged = await AIAnalyzer().mergePrivacyResults([chunk, chunk, chunk])

        #expect(merged.warnings == [warning])
        #expect(merged.criticalCount == 1)
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Test("Distinct issues at the same file and line keep distinct ids after merging")
    func mergedIssueIdsAreUnique() async {
        func issue(_ title: String) -> LogIssue {
            LogIssue(category: "error",
                     title: title,
                     description: "",
                     file: "",
                     line: 1,
                     occurrences: 1,
                     severity: .high,
                     suggestedFix: "")
        }
        func chunk(_ issues: [LogIssue]) -> LogIssueSummary {
            LogIssueSummary(executiveSummary: "",
                            issues: issues,
                            totalErrors: issues.count,
                            totalWarnings: 0,
                            totalFaults: 0,
                            patterns: [],
                            priorityActions: [])
        }

        let merged = await AIAnalyzer().mergeIssueResults([chunk([issue("Timeout")]),
                                                           chunk([issue("Decode failure"), issue("Timeout")])])

        #expect(merged.issues.count == 2)
        #expect(Set(merged.issues.map(\.id)).count == merged.issues.count)
    }
}
#endif
