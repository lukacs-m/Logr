//
//  AIAnalyzer.swift
//  Logr
//
//  Created by martin on 02/11/2025.
//

import Foundation
#if LOGR_SYSTEM_MODEL
import FoundationModels
#endif

/// Configuration for ``AIAnalyzer``.
public struct AnalyzerConfiguration: Sendable {
    /// Load the model before the first request.
    public let prewarmModel: Bool

    /// How many groups of a digest the model explains, at least 1: the first ones, which are the most severe and
    /// then the most frequent. The rest keep their template. The on-device model takes about 2 seconds a group.
    public let maxExplainedGroups: Int

    public init(prewarmModel: Bool = true, maxExplainedGroups: Int = 40) {
        self.prewarmModel = prewarmModel
        self.maxExplainedGroups = max(1, maxExplainedGroups)
    }

    public static var `default`: AnalyzerConfiguration {
        AnalyzerConfiguration()
    }
}

#if LOGR_SYSTEM_MODEL

/// Explains issue groups with the on-device Apple Intelligence model.
///
/// The first ``AnalyzerConfiguration/maxExplainedGroups`` groups go to the model in chunks sized to its context
/// window (`SystemLanguageModel.contextSize` minus the instructions, the output schema and room for the answer;
/// counted with `tokenCount(for:)` on 26.4 and later, estimated at 3 UTF-8 bytes per token before). Each chunk
/// yields a title, cause, fix and severity per group; then one more request writes the executive summary and
/// priority actions. File, line, counts and totals always come from the digest. A chunk that overflows the context
/// or that the guardrails refuse is split and retried; a single group that still fails is sent without its sample,
/// then left with its template, as are groups past the cap. A model error once some groups are explained keeps
/// them, and a failed overview leaves the counts summary.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, tvOS 26.0, watchOS 26.0, *)
public actor AIAnalyzer: LogAIAnalyzer {
    public let configuration: AnalyzerConfiguration
    private let model: SystemLanguageModel
    private var hasPrewarmed = false

    public init(configuration: AnalyzerConfiguration = .default,
                model: SystemLanguageModel = .default) {
        self.configuration = configuration
        self.model = model
    }

    public nonisolated var isAvailable: Bool {
        model.isAvailable
    }

    /// Why the model is or is not available.
    public var availabilityDescription: String {
        switch model.availability {
        case .available:
            "Foundation Model is ready"
        case let .unavailable(reason):
            "Unavailable: \(reason.localizedReason)"
        }
    }

    public func summarizeIssues(_ digest: LogIssueDigest,
                                onProgress: @escaping @MainActor @Sendable (AnalysisProgress) -> Void) async throws
        -> LogIssueSummary {
        if case let .unavailable(reason) = model.availability {
            throw AIAnalyzerError.modelUnavailable(reason.localizedReason)
        }
        guard !digest.isEmpty else { return .assemble(digest: digest, issues: [:], overview: nil) }
        do {
            return try await summary(of: digest, onProgress: onProgress)
        } catch let error as AIAnalyzerError {
            throw error
        } catch {
            // Token counting fails outside a chunk's own recovery, with the same errors.
            _ = try Self.failure(error)
            throw AIAnalyzerError.systemError(error)
        }
    }

    private func summary(of digest: LogIssueDigest,
                         onProgress: @escaping @MainActor @Sendable (AnalysisProgress) -> Void) async throws
        -> LogIssueSummary {
        let explained = Array(digest.groups.prefix(configuration.maxExplainedGroups))
        let total = explained.count
        await onProgress(.starting(totalGroups: total))
        let issues = try await Self.explain(chunks(of: explained)) { chunk in
            try await self.issues(for: chunk)
        } onChunk: { analyzed in
            await onProgress(AnalysisProgress(totalGroups: total, analyzedGroups: analyzed))
        }

        try Task.checkCancellation()
        let summary = LogIssueSummary.assemble(digest: digest, issues: issues, overview: nil)
        return try await LogIssueSummary.assemble(digest: digest, issues: issues,
                                                  overview: overview(of: summary, explained: total))
    }
}

// MARK: - Model output

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@Generable(description: "Explanations of numbered issue groups from an app's logs")
struct IssueInsightBatch {
    @Guide(description: "One insight per issue group", .maximumCount(AIAnalyzer.maxGroupsPerChunk))
    var insights: [IssueInsight]
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@Generable(description: "An explanation of one issue group")
struct IssueInsight {
    @Guide(description: "The number of the issue group", .range(0...(AIAnalyzer.maxGroupsPerChunk - 1)))
    var groupIndex: Int
    @Guide(description: "A short title, at most eight words")
    var title: String
    @Guide(description: "One sentence on the likely cause")
    var explanation: String
    @Guide(description: "One sentence on how to fix it")
    var suggestedFix: String
    @Guide(description: "How much the issue hurts users or stability")
    var severity: InsightSeverity
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@Generable
enum InsightSeverity {
    case critical, high, medium, low

    var severity: LogSeverity {
        switch self {
        case .critical: .critical
        case .high: .high
        case .medium: .medium
        case .low: .low
        }
    }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@Generable(description: "An overview of the issues found in an app's logs")
struct IssueOverview {
    @Guide(description: "Two or three sentences on the overall health of the app")
    var executiveSummary: String
    @Guide(description: "The most important actions, most urgent first", .maximumCount(5))
    var priorityActions: [String]
}

// MARK: - Requests

@available(iOS 26.0, macOS 26.0, visionOS 26.0, tvOS 26.0, watchOS 26.0, *)
extension AIAnalyzer {
    /// The guided `groupIndex` range, so also the most groups one chunk holds.
    static let maxGroupsPerChunk = 40
    // ponytail: estimated answer sizes; measure the model's real output if chunks overflow often.
    private static let tokensPerInsight = 120
    private static let overviewAnswerTokens = 400
    /// The prompt text around the group lines, and a margin for estimates.
    private static let promptOverhead = 150

    private static let instructions = """
    You explain problems found in an app's logs to its developers. Be concrete and brief. Base every statement \
    on the log lines given and never invent file names, line numbers or counts.
    """

    /// The groups split into runs whose prompt and expected answer fit the context window.
    private func chunks(of groups: [LogIssueGroup]) async throws -> [[LogIssueGroup]] {
        let budget = try await model.contextSize - instructionTokens()
            - tokens(in: IssueInsightBatch.generationSchema) - Self.promptOverhead
        var costs: [Int] = []
        for group in groups {
            // Counted with the widest group number: a group's place in its chunk is not known yet.
            let line = Self.line(for: group, index: Self.maxGroupsPerChunk - 1)
            try await costs.append(tokens(in: line) + Self.tokensPerInsight)
        }
        return Self.pack(groups, costs: costs, budget: budget, maxCount: Self.maxGroupsPerChunk)
    }

    /// Consecutive runs of `items` whose costs fit `budget`, at most `maxCount` each; an item over budget goes
    /// alone (its request overflows and is retried without its sample).
    static func pack<Item>(_ items: [Item], costs: [Int], budget: Int, maxCount: Int) -> [[Item]] {
        var chunks: [[Item]] = []
        var chunk: [Item] = []
        var used = 0
        for (item, cost) in zip(items, costs) {
            if !chunk.isEmpty, used + cost > budget || chunk.count == maxCount {
                chunks.append(chunk)
                chunk = []
                used = 0
            }
            chunk.append(item)
            used += cost
        }
        return chunk.isEmpty ? chunks : chunks + [chunk]
    }

    /// The chunks explained in order, sequentially: three parallel sessions measured 1.05x faster (phase 7), and
    /// iPadOS throttles sustained use. An ``AIAnalyzerError`` after some groups are explained (a rate limit late
    /// in a long run) stops there and keeps them; `onChunk` gets the number of items explained so far.
    static func explain<Item, Issue>(_ chunks: [[Item]],
                                     using explain: ([Item]) async throws -> [String: Issue],
                                     onChunk: (Int) async -> Void) async throws -> [String: Issue] {
        var issues: [String: Issue] = [:]
        var analyzed = 0
        for chunk in chunks {
            try Task.checkCancellation()
            do {
                try await issues.merge(explain(chunk)) { first, _ in first }
            } catch is AIAnalyzerError where !issues.isEmpty {
                break
            }
            analyzed += chunk.count
            await onChunk(analyzed)
        }
        return issues
    }

    /// Both halves of `items` explained in order; an ``AIAnalyzerError`` from the second half keeps the first
    /// half's issues, unless it explained none.
    static func split<Item, Issue>(_ items: [Item],
                                   using explain: ([Item]) async throws -> [String: Issue]) async throws
        -> [String: Issue] {
        let half = items.count / 2
        let first = try await explain(Array(items[..<half]))
        do {
            return try await first.merging(explain(Array(items[half...]))) { first, _ in first }
        } catch is AIAnalyzerError where !first.isEmpty {
            return first
        }
    }

    /// Issues for one chunk, keyed by group id; empty when the model will not explain these groups.
    private func issues(for chunk: [LogIssueGroup], withSamples: Bool = true) async throws -> [String: LogIssue] {
        // Also between the requests of a split chunk.
        try Task.checkCancellation()
        let lines = chunk.enumerated().map { Self.line(for: $1, index: $0, withSample: withSamples) }
        let prompt = """
        Explain each numbered issue group. A line shows the group number, level, category, source file, how many \
        times it was logged, the message template (values replaced by placeholders) and a sample message.

        \(lines.joined(separator: "\n"))

        Answer with one insight per group, using the group number.
        """
        do {
            let batch = try await session().respond(to: prompt, generating: IssueInsightBatch.self).content
            return LogIssueSummary.issues(from: batch.insights.map {
                LogIssueSummary.Insight(groupIndex: $0.groupIndex, title: $0.title, explanation: $0.explanation,
                                        suggestedFix: $0.suggestedFix, severity: $0.severity.severity)
            }, chunk: chunk)
        } catch {
            // Overflows and refusals split down to the group at fault, retried once without its sample.
            _ = try Self.failure(error)
            if chunk.count > 1 {
                return try await Self.split(chunk) { try await issues(for: $0, withSamples: withSamples) }
            }
            return withSamples ? try await issues(for: chunk, withSamples: false) : [:]
        }
    }

    /// The executive summary and priority actions, over as many of the first `explained` issues as fit; `nil` when
    /// the request fails, so the issues already explained are kept.
    private func overview(of summary: LogIssueSummary, explained: Int) async throws -> (String, [String])? {
        // Token counting included: nothing here may cost the issues already explained.
        do {
            var budget = try await model.contextSize - instructionTokens()
                - tokens(in: IssueOverview.generationSchema) - Self.promptOverhead - Self.overviewAnswerTokens
            var lines: [String] = []
            for issue in summary.issues.prefix(explained) {
                let line = "- [\(issue.severity.description)] \(issue.title) (\(issue.group.count)×): "
                    + issue.explanation
                budget -= try await tokens(in: line)
                guard budget >= 0 else { break }
                lines.append(line)
            }
            let prompt = """
            These issues were found in an app's logs, most severe first, with how often each was logged:

            \(lines.joined(separator: "\n"))

            In total: \(summary.totalErrors) errors, \(summary.totalWarnings) warnings, \(summary.totalFaults) faults.
            Write an executive summary and up to five priority actions.
            """
            let overview = try await session().respond(to: prompt, generating: IssueOverview.self).content
            return (overview.executiveSummary, overview.priorityActions)
        } catch {
            // The model may report a cancelled request as one of its own errors.
            try Task.checkCancellation()
            if error is CancellationError {
                throw error
            }
            return nil
        }
    }

    private func session() -> LanguageModelSession {
        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        // The model load is shared by every session, so one prewarm is enough.
        if configuration.prewarmModel, !hasPrewarmed {
            session.prewarm()
            hasPrewarmed = true
        }
        return session
    }

    private static func line(for group: LogIssueGroup, index: Int, withSample: Bool = true) -> String {
        var line = "[\(index)] \(group.level.rawValue), \(group.category.rawValue), \(group.file), \(group.count)×: "
            + group.template
        if withSample, group.sampleMessage != group.template {
            line += " | sample: \(group.sampleMessage)"
        }
        return line
    }

    private func tokens(in text: String) async throws -> Int {
        guard #available(iOS 26.4, macOS 26.4, visionOS 26.4, *) else { return text.utf8.count / 3 }
        return try await model.tokenCount(for: text)
    }

    private func instructionTokens() async throws -> Int {
        guard #available(iOS 26.4, macOS 26.4, visionOS 26.4, *) else { return Self.instructions.utf8.count / 3 }
        return try await model.tokenCount(for: Instructions(Self.instructions))
    }

    private func tokens(in schema: GenerationSchema) async throws -> Int {
        // ponytail: fixed estimate for an output schema before 26.4, which cannot count one.
        guard #available(iOS 26.4, macOS 26.4, visionOS 26.4, *) else { return 300 }
        return try await model.tokenCount(for: schema)
    }

    enum Failure {
        case contextOverflow
        case refused
    }

    /// Classifies the failures a chunk recovers from; anything else is thrown as an ``AIAnalyzerError`` (or as is,
    /// for cancellation).
    static func failure(_ error: any Error) throws -> Failure {
        if error is CancellationError {
            throw error
        }
        // The 27 SDKs (FoundationModels 2.0) replace `GenerationError` with `LanguageModelError`; CI builds with
        // 26.x.
        #if canImport(FoundationModels, _version: 2.0)
        if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *), let error = error as? LanguageModelError {
            switch error {
            case .contextSizeExceeded: return .contextOverflow
            case .guardrailViolation, .refusal: return .refused
            case .rateLimited: throw AIAnalyzerError.rateLimited
            default: throw AIAnalyzerError.systemError(error)
            }
        }
        #endif
        guard let generationError = error as? LanguageModelSession.GenerationError else {
            throw AIAnalyzerError.systemError(error)
        }
        switch generationError {
        case .exceededContextWindowSize: return .contextOverflow
        case .guardrailViolation, .refusal: return .refused
        case .rateLimited: throw AIAnalyzerError.rateLimited
        default: throw AIAnalyzerError.systemError(error)
        }
    }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private extension SystemLanguageModel.Availability.UnavailableReason {
    var localizedReason: String {
        switch self {
        case .deviceNotEligible:
            "Device is not eligible for Apple Intelligence analysis"
        case .appleIntelligenceNotEnabled:
            "Apple Intelligence is not enabled on this device"
        case .modelNotReady:
            "Apple Intelligence model is not ready"
        @unknown default:
            "Unknown reason"
        }
    }
}

#else
/// Reports native analysis as unavailable on platforms without the on-device system language model
/// (tvOS, watchOS).
@available(iOS 26.0, macOS 26.0, visionOS 26.0, tvOS 26.0, watchOS 26.0, *)
public actor AIAnalyzer: LogAIAnalyzer {
    public let configuration: AnalyzerConfiguration
    public nonisolated var isAvailable: Bool {
        false
    }

    public var availabilityDescription: String {
        "The on-device system language model is unavailable on this platform."
    }

    public init(configuration: AnalyzerConfiguration = .default) {
        self.configuration = configuration
    }

    public func summarizeIssues(_ digest: LogIssueDigest,
                                onProgress: @escaping @MainActor @Sendable (AnalysisProgress) -> Void) async throws
        -> LogIssueSummary {
        throw AIAnalyzerError.modelUnavailable(availabilityDescription)
    }
}
#endif
