import Foundation
import Observation
@testable import Logr
import LogrTesting
import Testing

@Suite("Export privacy")
struct ExportPrivacyTests {
    private static let entry = LogEntry(level: .info, category: .user, subsystem: "s",
                                        message: "Signed in zoë@example.com after 3 tries",
                                        file: "App/Login.swift", function: "f()", line: 7, privateRanges: [10..<26])

    private func export(_ entries: [LogEntry], _ format: ExportFormat, includingPrivateValues: Bool) async throws
        -> String {
        try await String(decoding: LogExporter.serialize(entries, format: format,
                                                         includingPrivateValues: includingPrivateValues),
                         as: UTF8.self)
    }

    @Test(arguments: ExportFormat.allCases)
    func exportsReplacePrivateValuesByDefault(format: ExportFormat) async throws {
        let text = try await export([Self.entry], format, includingPrivateValues: false)
        #expect(text.contains("Signed in <private> after 3 tries"))
        #expect(!text.contains("zoë"))
        #expect(!text.contains("privateRanges"))
    }

    @Test(arguments: ExportFormat.allCases)
    func exportsKeepPrivateValuesWhenAsked(format: ExportFormat) async throws {
        let text = try await export([Self.entry], format, includingPrivateValues: true)
        #expect(text.contains("Signed in zoë@example.com after 3 tries"))
    }

    @Test func jsonWithPrivateValuesKeepsTheirRanges() async throws {
        let data = try await LogExporter.serialize([Self.entry], format: .json, includingPrivateValues: true)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode([LogEntry].self, from: data).map(\.privateRanges) == [[10..<26]])
    }

    @Test(arguments: [
        ([-5..<3], "<private>defgh"),
        ([2..<100], "ab<private>"),
        ([4..<6, 0..<5], "<private>gh"),
        ([50..<60], "abcdefgh"),
        ([1..<2, 1..<2], "a<private>cdefgh"),
        ([1..<2, 2..<3], "a<private><private>defgh")
    ])
    func malformedRangesAreClampedAndMerged(ranges: [Range<Int>], expected: String) {
        let entry = LogEntry(level: .info, category: .user, subsystem: "s", message: "abcdefgh", privateRanges: ranges)
        let redacted = entry.redactingPrivateValues()
        #expect(redacted.message == expected)
        #expect(redacted.privateRanges.isEmpty)
    }

    @Test func aRangeInsideACharacterNeverLeaksIt() {
        let entry = LogEntry(level: .info, category: .user, subsystem: "s", message: "é!", privateRanges: [1..<2])
        let message = entry.redactingPrivateValues().message
        #expect(!message.contains("é"))
        #expect(message.hasSuffix("<private>!"))
    }

    @MainActor
    @Test func logRExportsReplacePrivateValuesUnlessAsked() async throws {
        let logger = LogR(cryptoService: LoggerCryptoService(store: InMemoryKeychainStore()),
                          configuration: LogrConfiguration(mirrorToOSLog: false, storesPrivateValues: true))
        logger.info("user \("zoë")")

        let masked = try await String(decoding: logger.exportLogs(format: .txt), as: UTF8.self)
        let full = try await String(decoding: logger.exportLogs(format: .txt, includingPrivateValues: true),
                                    as: UTF8.self)

        #expect(masked.contains("user <private>"))
        #expect(full.contains("user zoë"))
    }

    @MainActor
    @Test func aConformerOverridingTheOneArgumentExportIsStillCalled() async throws {
        let service: any LogRService = LegacyExportService()
        #expect(try await service.exportLogs(format: .json) == Data("custom".utf8))
    }

    // MARK: - CSV formula injection

    @Test(arguments: [#"=HYPERLINK("http://x","y")"#, "+1", "-2", "@SUM(A1)", "\tx", "\rx", "\r\nx"])
    func csvFieldsThatSpreadsheetsRunAsFormulasArePrefixed(value: String) async throws {
        let entry = LogEntry(level: .info, category: LogCategory(rawValue: value), subsystem: value, message: value,
                             file: value, function: value, line: 7, metadata: [value: .string("v")])

        let rows = try await parseCSV(export([entry], .csv, includingPrivateValues: false))

        let neutralised = "'" + value
        #expect(rows.last?.dropFirst(2) == ["'" + entry.category.description, neutralised, neutralised, neutralised,
                                            neutralised, "7", "'\(value)=v"])
    }

    @Test(arguments: ["Total = 3", " =1", "a-b", "x@y"])
    func csvFieldsThatOnlyContainThoseCharactersAreUntouched(value: String) async throws {
        let entry = LogEntry(level: .info, category: .user, subsystem: "s", message: value)

        let rows = try await parseCSV(export([entry], .csv, includingPrivateValues: false))

        #expect(rows.last?[4] == value)
    }
}

/// Written against Logr 1.x: overrides `exportLogs(format:)` only.
@Observable
private final class LegacyExportService: LogRService {
    @MainActor var recentLogs: LogEntries {
        []
    }

    @MainActor var canAnalyseLogs: Bool {
        false
    }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)
    @MainActor var privacyAnalysisResult: PrivacyAnalysisResult? {
        nil
    }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)
    @MainActor var logIssueSummary: LogIssueSummary? {
        nil
    }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)
    @MainActor var analysisProgress: AnalysisProgress? {
        nil
    }

    nonisolated func record(level: LogLevel, message: @autoclosure () -> LogMessage, category: LogCategory,
                            file: String, function: String, line: Int,
                            metadata: @autoclosure () -> [String: LogMetadataValue]?) {}

    func exportLogs(format: ExportFormat) async throws -> Data {
        Data("custom".utf8)
    }

    func clearLogs() async throws {}

    func flush() async {}

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)
    func scanForPrivacyIssues() async throws -> PrivacyAnalysisResult {
        throw AIAnalyzerError.missingAnalyzer
    }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)
    func summarizeIssues() async throws -> LogIssueSummary {
        throw AIAnalyzerError.missingAnalyzer
    }
}
