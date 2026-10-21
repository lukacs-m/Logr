import Collections
import DequeModule
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Logr
@testable import LogrUI
import LogrTesting

@MainActor
@Suite("LogrUI regressions")
struct LogrUIRegressionTests {
    private static func entry(_ message: String) -> LogEntry {
        LogEntry(level: .info, category: .system, subsystem: "test", message: message)
    }

    private func makeLogger(maxLogEntries: Int = 100) throws -> LogR {
        LogR(cryptoService: LoggerCryptoService(store: InMemoryKeychainStore()),
             configuration: LogrConfiguration(maxLogEntries: maxLogEntries, mirrorToOSLog: false))
    }

    @available(macOS 15.2, iOS 18.2, tvOS 18.2, watchOS 11.2, *)
    @Test func rollingCacheUpdatesStatisticsAndSharedContent() async throws {
        let logger = try makeLogger(maxLogEntries: 100)
        for index in 1 ... 100 {
            logger.info("old \(index)")
        }
        let initial = Array(logger.recentLogs)
        #expect(await logger.logStatistics().countByLevel[.info] == 100)

        logger.error("replacement")
        let replacement = Array(logger.recentLogs)
        #expect(initial.count == replacement.count)
        #expect(initial != replacement)
        let statistics = await logger.logStatistics()
        #expect(statistics.countByLevel[.info] == 99)
        #expect(statistics.countByLevel[.error] == 1)

        let item = ShareItem.logExport(from: logger, format: .json)
        let data = try await item.exported(as: .json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = try decoder.decode([LogEntry].self, from: data)
        #expect(entries.map(\.message) == ["replacement"] + (2 ... 100).reversed().map { "old \($0)" })
    }

    @available(macOS 15.2, iOS 18.2, tvOS 18.2, watchOS 11.2, *)
    @Test(arguments: ExportFormat.allCases)
    func nativeExportPreservesFormatAndBytes(format: ExportFormat) async throws {
        let logger = try makeLogger()
        logger.info("export me")
        let expected = try await LogExporter.serialize(Array(logger.recentLogs), format: format,
                                                      includingPrivateValues: false)
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
        service.storedLogs = [Self.entry("token=secret")]
        service.export = { Data("[redacted]".utf8) }
        let item = ShareItem.logExport(from: service, format: .json)

        #expect(service.exportCallCount == 0)
        let data = try await item.exported(as: .json)
        #expect(String(decoding: data, as: UTF8.self) == "[redacted]")
        #expect(service.exportCallCount == 1)
    }

    @Test func hiddenSummaryPanelDoesNoWorkAndShowingItFetchesImmediately() async throws {
        let service = StubLogService()
        service.storedLogs = [Self.entry("visible")]
        let refresher = LogStatisticsRefresher()

        await refresher.refresh(from: service, isActive: false)
        #expect(service.statisticsCallCount == 0)
        #expect(refresher.statistics.totalCount == 0)

        await refresher.refresh(from: service, isActive: true)
        #expect(service.statisticsCallCount == 1)
        #expect(refresher.statistics.totalCount == 1)

        service.storedLogs = []
        await refresher.refresh(from: service)
        #expect(refresher.statistics.totalCount == 0)
    }

    @Test func requestsArrivingDuringAComputationCoalesceIntoOneRecompute() async throws {
        let service = StubLogService()
        let gate = RefreshGate()
        service.beforeStatistics = { await gate.wait() }
        service.storedLogs = [Self.entry("first")]
        let refresher = LogStatisticsRefresher()

        let inFlight = Task { await refresher.refresh(from: service) }
        try await service.waitForStatisticsStart(count: 1)

        service.storedLogs = [Self.entry("first"), Self.entry("second")]
        let coalesced = [Task { await refresher.refresh(from: service) },
                         Task { await refresher.refresh(from: service) }]
        for _ in 0..<10 {
            await Task.yield()
        }
        #expect(service.statisticsCallCount == 1)
        #expect(refresher.statistics.totalCount == 0)

        await gate.open()
        await inFlight.value
        for request in coalesced {
            await request.value
        }

        #expect(service.statisticsCallCount == 2)
        #expect(service.maxConcurrentStatistics == 1)
        #expect(refresher.statistics.totalCount == 2)
    }

    @Test func cancellationDoesNotDiscardACompletedComputation() async throws {
        let service = StubLogService()
        let gate = RefreshGate()
        service.beforeStatistics = { await gate.wait() }
        service.storedLogs = [Self.entry("only")]
        let refresher = LogStatisticsRefresher()

        let inFlight = Task { await refresher.refresh(from: service) }
        try await service.waitForStatisticsStart(count: 1)
        inFlight.cancel()
        await gate.open()
        await inFlight.value

        #expect(refresher.statistics.totalCount == 1)
    }

    @Test func resetInvalidatesAnInFlightComputation() async throws {
        let service = StubLogService()
        let gate = RefreshGate()
        service.beforeStatistics = { await gate.wait() }
        service.storedLogs = [Self.entry("stale")]
        let refresher = LogStatisticsRefresher()

        let inFlight = Task { await refresher.refresh(from: service) }
        try await service.waitForStatisticsStart(count: 1)
        refresher.reset()
        await gate.open()
        await inFlight.value
        #expect(refresher.statistics.totalCount == 0)

        await refresher.refresh(from: service)
        #expect(refresher.statistics.totalCount == 1)
    }

    @Test func refreshQueuedDuringAnInvalidatedComputationStillPublishes() async throws {
        let service = StubLogService()
        let gate = RefreshGate()
        service.beforeStatistics = { await gate.wait() }
        service.storedLogs = [Self.entry("first")]
        let refresher = LogStatisticsRefresher()

        let inFlight = Task { await refresher.refresh(from: service) }
        try await service.waitForStatisticsStart(count: 1)

        await refresher.refresh(from: service, isActive: false)
        service.storedLogs = [Self.entry("first"), Self.entry("second")]
        let requeued = Task { await refresher.refresh(from: service) }
        for _ in 0..<10 {
            await Task.yield()
        }
        #expect(service.statisticsCallCount == 1)

        await gate.open()
        await inFlight.value
        await requeued.value

        #expect(refresher.statistics.totalCount == 2)
        #expect(service.maxConcurrentStatistics == 1)
    }

    @available(macOS 15.2, iOS 18.2, tvOS 18.2, watchOS 11.2, *)
    @Test func failedSerializationSurfacesInsteadOfSharingEmptyBytes() async throws {
        let service = StubLogService()
        service.storedLogs = [Self.entry("hi")]
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

/// A conformer that overrides ``LogRService/exportLogs(format:includingPrivateValues:)`` and ``LogRService/logStatistics()``
/// — the documented extension points for redaction or for reporting persisted history rather than the
/// in-memory cache. Its logs are deliberately absent from `recentLogs`, so a caller that bypasses an
/// override sees an empty service.
private final class StubLogService: LogRService {
    @MainActor var storedLogs: Deque<LogEntry> = []
    @MainActor var export: @Sendable () async throws -> Data = { Data() }
    @MainActor var beforeStatistics: (@Sendable () async -> Void)?
    @MainActor private(set) var exportCallCount = 0
    @MainActor private(set) var statisticsCallCount = 0
    @MainActor private(set) var maxConcurrentStatistics = 0
    @MainActor private var runningStatistics = 0

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

    nonisolated func record(level: LogLevel,
                            message: @autoclosure () -> LogMessage,
                            category: LogCategory,
                            file: String,
                            function: String,
                            line: Int,
                            metadata: @autoclosure () -> [String: LogMetadataValue]?) {}

    func exportLogs(format: ExportFormat, includingPrivateValues: Bool) async throws -> Data {
        let export = await MainActor.run {
            exportCallCount += 1
            return self.export
        }
        return try await export()
    }

    func logStatistics() async -> LogStatistics {
        let gate = await MainActor.run {
            statisticsCallCount += 1
            runningStatistics += 1
            maxConcurrentStatistics = max(maxConcurrentStatistics, runningStatistics)
            return beforeStatistics
        }
        await gate?()
        let snapshot = await MainActor.run {
            runningStatistics -= 1
            return Array(storedLogs)
        }
        return await LogStatisticsComputer.compute(from: snapshot)
    }

    /// Yields until `count` computations have begun, so a test can act while one is suspended.
    @MainActor
    func waitForStatisticsStart(count: Int) async throws {
        for _ in 0..<10_000 {
            if statisticsCallCount >= count { return }
            await Task.yield()
        }
        throw StubTimeout()
    }

    func clearLogs() async throws {
        await MainActor.run { storedLogs = [] }
    }

    func flush() async {}

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)
    @MainActor func scanForPrivacyIssues() async throws -> PrivacyAnalysisResult {
        throw CancellationError()
    }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)
    @MainActor func summarizeIssues() async throws -> LogIssueSummary {
        throw CancellationError()
    }
}

private struct StubTimeout: Error {}

/// A latch a test opens once it has observed the state it wanted to act on.
private actor RefreshGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters = []
        for waiter in pending {
            waiter.resume()
        }
    }
}
