import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Logr
@testable import LogrUI

@MainActor
@Suite("LogrUI regressions")
struct LogrUIRegressionTests {
    @available(macOS 15.2, iOS 18.2, tvOS 18.2, watchOS 11.2, *)
    @Test func rollingCacheUpdatesStatisticsAndSharedContent() async throws {
        let logger = LogR(cryptoService: try LoggerCryptoService(store: LockedKeychainStore()),
                          configuration: LogrConfiguration(maxLogEntries: 2, mirrorToOSLog: false))
        logger.info("old one")
        logger.info("old two")
        let initial = Array(logger.recentLogs)
        let first = try await LogViewerData.load(initial, includeSharing: true)
        #expect(first.statistics.countByLevel[.info] == 2)

        logger.error("replacement")
        let replacement = Array(logger.recentLogs)
        #expect(initial.count == replacement.count)
        #expect(initial != replacement)
        let updated = try await LogViewerData.load(replacement, includeSharing: true)
        #expect(updated.statistics.countByLevel[.info] == 1)
        #expect(updated.statistics.countByLevel[.error] == 1)
        let item = try #require(updated.shareItems[.json])
        let data = try await item.exported(as: .json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = try decoder.decode([LogEntry].self, from: data)
        #expect(entries.map(\.message) == ["replacement", "old two"])
    }

    @available(macOS 15.2, iOS 18.2, tvOS 18.2, watchOS 11.2, *)
    @Test(arguments: ExportFormat.allCases)
    func nativeExportPreservesFormatAndBytes(format: ExportFormat) async throws {
        let logs = [LogEntry(level: .info, category: .system, subsystem: "test", message: "export me")]
        let result = try await LogViewerData.load(logs, includeSharing: true)
        let item = try #require(result.shareItems[format])
        let expected = try await LogExporter.serialize(logs, format: format)
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

    @Test func canceledRefreshDoesNotReturnPublishableData() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await LogViewerData.load([], includeSharing: true)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func clearedOrDisabledSharingHasNoPayloads() async throws {
        let empty = try await LogViewerData.load([], includeSharing: true)
        #expect(empty.statistics.totalCount == 0)
        #expect(empty.shareItems.isEmpty)
        let logs = [LogEntry(level: .error, category: .system, subsystem: "test", message: "error")]
        let disabled = try await LogViewerData.load(logs, includeSharing: false)
        #expect(disabled.statistics.countByLevel[.error] == 1)
        #expect(disabled.shareItems.isEmpty)
    }
}
