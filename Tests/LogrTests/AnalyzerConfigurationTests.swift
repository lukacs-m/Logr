import Testing
@testable import Logr

@Suite("Analyzer Configuration")
struct AnalyzerConfigurationTests {
    @Test("maxExplainedGroups defaults to 40 and keeps at least one group")
    func explainedGroups() {
        #expect(AnalyzerConfiguration().maxExplainedGroups == 40)
        #expect(AnalyzerConfiguration(maxExplainedGroups: 0).maxExplainedGroups == 1)
    }
}
