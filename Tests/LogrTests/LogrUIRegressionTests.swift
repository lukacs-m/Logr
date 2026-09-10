import Collections
import DequeModule
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Logr
@testable import LogrUI

@MainActor
@Suite("LogrUI regressions")
struct LogrUIRegressionTests {
    private func makeLogger(maxLogEntries: Int = 100) throws -> LogR {
        LogR(cryptoService: try LoggerCryptoService(store: LockedKeychainStore()),
             configuration: LogrConfiguration(maxLogEntries: maxLogEntries, mirrorToOSLog: false))
    }

    @available(macOS 15.2, iOS 18.2, tvOS 18.2, watchOS 11.2, *)
    @Test func rollingCacheUpdatesStatisticsAndSharedContent() async throws {
        let logger = try makeLogger(maxLogEntries: 2)
        logger.info("old one")
        logger.info("old two")
        let initial = Array(logger.recentLogs)
        #expect(await logger.logStatistics().countByLevel[.info] == 2)

        logger.error("replacement")
        let replacement = Array(logger.recentLogs)
        #expect(initial.count == replacement.count)
        #expect(initial != replacement)
        let statistics = await logger.logStatistics()
        #expect(statistics.countByLevel[.info] == 1)
        #expect(statistics.countByLevel[.error] == 1)

        let item = ShareItem.logExport(from: logger, format: .json)
        let data = try await item.exported(as: .json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = try decoder.decode([LogEntry].self, from: data)
        #expect(entries.map(\.message) == ["replacement", "old two"])
    }

    @available(macOS 15.2, iOS 18.2, tvOS 18.2, watchOS 11.2, *)
    @Test(arguments: ExportFormat.allCases)
    func nativeExportPreservesFormatAndBytes(format: ExportFormat) async throws {
        let logger = try makeLogger()
        logger.info("export me")
        let expected = try await LogExporter.serialize(Array(logger.recentLogs), format: format)
        let item = ShareItem.logExport(from: logger, format: format)
        #expect(item.fileName == "logs.\(format.fileExtension)")
        #expect(item.exportedContentTypes().contains(format.contentType))
        #expect(try await item.exported(as: format.contentType) == expected)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try await item.export(to: directory, contentType: format.contentType)
        #expect(url.pathExtension == format.fileExtension)
        #expect(try Data(contentsOf: url) == expected)
    }

    @available(macOS 15.2, iOS 18.2, tvOS 18.2, watchOS 11.2, *)
    @Test func sharingUsesTheServiceExportSoOverridesAreHonored() async throws {
        let service = StubLogService()
        service.entries = [LogEntry(level: .info, category: .system, subsystem: "test", message: "token=secret")]
        service.export = { Data("[redacted]".utf8) }
        let item = ShareItem.logExport(from: service, format: .json)

        #expect(service.exportCallCount == 0)
        let data = try await item.exported(as: .json)
        #expect(String(decoding: data, as: UTF8.self) == "[redacted]")
        #expect(service.exportCallCount == 1)
    }

    @Test func statisticsPublishWithoutWaitingForSerialization() async throws {
        let service = StubLogService()
        service.entries = [LogEntry(level: .error, category: .system, subsystem: "test", message: "boom")]
        service.export = {
            try await Task.sleep(for: .seconds(60))
            return Data()
        }

        let statistics = await service.logStatistics()
        #expect(statistics.countByLevel[.error] == 1)
        #expect(service.exportCallCount == 0)
    }

    @available(macOS 15.2, iOS 18.2, tvOS 18.2, watchOS 11.2, *)
    @Test func failedSerializationSurfacesInsteadOfSharingEmptyBytes() async throws {
        let service = StubLogService()
        service.entries = [LogEntry(level: .info, category: .system, subsystem: "test", message: "hi")]
        service.export = { throw LogExportError.encodingFailed }
        let item = ShareItem.logExport(from: service, format: .json)

        await #expect(throws: (any Error).self) { try await item.exported(as: .json) }
    }

    @Test func clearedLogsProduceEmptyStatisticsAndPayload() async throws {
        let logger = try makeLogger()
        logger.info("to be cleared")
        try await logger.clearLogs()

        #expect(await logger.logStatistics().totalCount == 0)
        #expect(try await logger.exportLogs(format: .json).isEmpty)
    }
}

/// A conformer that overrides ``LogRService/exportLogs(format:)`` — the documented extension point
/// for redaction or exporting persisted history — and records when the override is invoked.
private final class StubLogService: LogRService, @unchecked Sendable {
    var entries: Deque<LogEntry> = []
    var export: @Sendable () async throws -> Data = { Data() }
    private(set) var exportCallCount = 0

    @MainActor var recentLogs: Deque<LogEntry> {
        entries
    }

    @MainActor var canAnalyseLogs: Bool {
        false
    }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    @MainActor var privacyAnalysisResult: PrivacyAnalysisResult? {
        nil
    }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    @MainActor var logIssueSummary: LogIssueSummary? {
        nil
    }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    @MainActor var analysisProgress: AnalysisProgress? {
        nil
    }

    nonisolated func log(level: LogLevel,
                         message: @autoclosure () -> String,
                         category: LogCategory,
                         file: String,
                         function: String,
                         line: Int,
                         metadata: [String: LogMetadataValue]?) {}

    func exportLogs(format: ExportFormat) async throws -> Data {
        exportCallCount += 1
        return try await export()
    }

    func clearLogs() async throws {
        await MainActor.run { entries = [] }
    }

    func flush() async {}

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    @MainActor func scanForPrivacyIssues() async throws -> PrivacyAnalysisResult {
        throw CancellationError()
    }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
    @MainActor func summarizeIssues() async throws -> LogIssueSummary {
        throw CancellationError()
    }
}
