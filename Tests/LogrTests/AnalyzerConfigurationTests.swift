import Testing
@testable import Logr

@Suite("Analyzer Configuration")
struct AnalyzerConfigurationTests {
    @Test("Default concurrency matches the documented 2-3 recommendation")
    func testDefaultConcurrency() {
        #expect(AnalyzerConfiguration().maxConcurrentChunks == 3)
    }

    @Test("maxConcurrentChunks is clamped to a safe range")
    func testConcurrencyClamping() {
        // On-device models are resource constrained; a pathological value is capped.
        #expect(AnalyzerConfiguration(maxConcurrentChunks: 1000).maxConcurrentChunks == 8)
        // And the lower bound stays at least 1.
        #expect(AnalyzerConfiguration(maxConcurrentChunks: 0).maxConcurrentChunks == 1)
        #expect(AnalyzerConfiguration(maxConcurrentChunks: -5).maxConcurrentChunks == 1)
    }
}
