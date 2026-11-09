#if LOGR_SYSTEM_MODEL
import FoundationModels
@testable import Logr
import Testing

@Suite("AIAnalyzer failure classification")
struct AIAnalyzerFailureTests {
    @available(macOS 26.0, iOS 26.0, *)
    private static var context: LanguageModelSession.GenerationError.Context {
        .init(debugDescription: "test")
    }

    @available(macOS 26.0, iOS 26.0, *)
    @Test func overflowAndRefusalsAreRecoverable() throws {
        #expect(try AIAnalyzer.failure(LanguageModelSession.GenerationError.exceededContextWindowSize(Self.context))
            == .contextOverflow)
        #expect(try AIAnalyzer.failure(LanguageModelSession.GenerationError.guardrailViolation(Self.context))
            == .refused)
    }

    @available(macOS 26.0, iOS 26.0, *)
    @Test func rateLimitingIsSurfaced() {
        #expect {
            try AIAnalyzer.failure(LanguageModelSession.GenerationError.rateLimited(Self.context))
        } throws: { error in
            if case .rateLimited = error as? AIAnalyzerError { return true }
            return false
        }
    }

    @available(macOS 26.0, iOS 26.0, *)
    @Test func cancellationStaysCancellation() {
        #expect(throws: CancellationError.self) { try AIAnalyzer.failure(CancellationError()) }
    }

    @available(macOS 26.0, iOS 26.0, *)
    @Test func anythingElseIsASystemError() {
        struct Other: Error {}
        #expect {
            try AIAnalyzer.failure(Other())
        } throws: { error in
            if case let .systemError(underlying) = error as? AIAnalyzerError { return underlying is Other }
            return false
        }
    }
}
@Suite("AIAnalyzer chunk packing")
struct AIAnalyzerPackingTests {
    @available(macOS 26.0, iOS 26.0, *)
    @Test func runsFitTheBudgetInOrder() {
        #expect(AIAnalyzer.pack(Array(0..<6), costs: [40, 40, 30, 50, 10, 60], budget: 100, maxCount: 10)
            == [[0, 1], [2, 3, 4], [5]])
    }

    @available(macOS 26.0, iOS 26.0, *)
    @Test func countIsCapped() {
        #expect(AIAnalyzer.pack(Array(0..<5), costs: Array(repeating: 1, count: 5), budget: 100, maxCount: 2)
            == [[0, 1], [2, 3], [4]])
    }

    @available(macOS 26.0, iOS 26.0, *)
    @Test func anOversizedItemGoesAlone() {
        #expect(AIAnalyzer.pack(Array(0..<3), costs: [10, 500, 10], budget: 100, maxCount: 10) == [[0], [1], [2]])
        // A budget below zero (instructions larger than the context) still yields one item per chunk.
        #expect(AIAnalyzer.pack(Array(0..<2), costs: [10, 10], budget: -5, maxCount: 10) == [[0], [1]])
        #expect(AIAnalyzer.pack([Int](), costs: [], budget: 100, maxCount: 10).isEmpty)
    }
}

@Suite("AIAnalyzer chunk runs")
struct AIAnalyzerChunkRunTests {
    @available(macOS 26.0, iOS 26.0, *)
    @Test func aLaterFailureKeepsWhatWasExplained() async throws {
        var reported: [Int] = []
        let explained = try await AIAnalyzer.explain([["a", "b"], ["c"], ["d"]]) { chunk in
            guard chunk != ["c"] else { throw AIAnalyzerError.rateLimited }
            return Dictionary(uniqueKeysWithValues: chunk.map { ($0, $0.uppercased()) })
        } onChunk: { reported.append($0) }
        #expect(explained == ["a": "A", "b": "B"])
        #expect(reported == [2])
    }

    @available(macOS 26.0, iOS 26.0, *)
    @Test func aFailureBeforeAnyGroupIsThrown() async {
        await #expect(throws: AIAnalyzerError.self) {
            _ = try await AIAnalyzer.explain([["a"]]) { _ -> [String: String] in
                throw AIAnalyzerError.rateLimited
            } onChunk: { _ in }
        }
    }

    @available(macOS 26.0, iOS 26.0, *)
    @Test func cancellationIsNeverSwallowed() async {
        await #expect(throws: CancellationError.self) {
            _ = try await AIAnalyzer.explain([["a"], ["b"]]) { chunk -> [String: String] in
                guard chunk == ["a"] else { throw CancellationError() }
                return ["a": "A"]
            } onChunk: { _ in }
        }
    }

    @available(macOS 26.0, iOS 26.0, *)
    @Test func aSplitKeepsTheFirstHalfWhenTheSecondFails() async throws {
        let explained = try await AIAnalyzer.split(["a", "b", "c"]) { half in
            guard half == ["a"] else { throw AIAnalyzerError.rateLimited }
            return ["a": "A"]
        }
        #expect(explained == ["a": "A"])
    }

    @available(macOS 26.0, iOS 26.0, *)
    @Test func aSplitThrowsWhenNothingWasExplained() async {
        await #expect(throws: AIAnalyzerError.self) {
            _ = try await AIAnalyzer.split(["a", "b"]) { half -> [String: String] in
                guard half == ["a"] else { throw AIAnalyzerError.rateLimited }
                return [:]
            }
        }
        await #expect(throws: CancellationError.self) {
            _ = try await AIAnalyzer.split(["a", "b"]) { half -> [String: String] in
                guard half == ["a"] else { throw CancellationError() }
                return ["a": "A"]
            }
        }
    }
}
#endif
