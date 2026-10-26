//
//  URLSession+Logging.swift
//  LogrNetwork
//

import Foundation
import Logr
import os

/// The values of `URLSessionTaskMetrics` an entry keeps, read in the delegate callback.
struct HTTPMetrics: Sendable {
    var duration: TimeInterval
    var networkProtocol: String?
    var isReusedConnection: Bool?
    var requestBodyBytesSent = 0
    /// The headers of the first transaction's request, the one `http.url` shows, URLSession's own included; `nil`
    /// when there is no transaction.
    var sentHeaders: [String: String]?
    var phases: [(key: String, milliseconds: Double)] = []

    init(_ metrics: URLSessionTaskMetrics) {
        duration = metrics.taskInterval.duration
        guard let last = metrics.transactionMetrics.last else { return }
        requestBodyBytesSent = Int(clamping: last.countOfRequestBodyBytesSent)
        // A redirect's transactions go to other URLs; the first matches the logged one.
        sentHeaders = metrics.transactionMetrics.first?.request.allHTTPHeaderFields
        if last.resourceFetchType == .networkLoad {
            networkProtocol = last.networkProtocolName
            isReusedConnection = last.isReusedConnection
        }
        let spans: [(String, Date?, Date?)] = [
            (HTTPLogFields.domainLookupMilliseconds, last.domainLookupStartDate, last.domainLookupEndDate),
            (HTTPLogFields.connectMilliseconds, last.connectStartDate,
             last.secureConnectionStartDate ?? last.connectEndDate),
            (HTTPLogFields.secureConnectionMilliseconds, last.secureConnectionStartDate,
             last.secureConnectionEndDate),
            (HTTPLogFields.requestMilliseconds, last.requestStartDate, last.requestEndDate),
            (HTTPLogFields.waitMilliseconds, last.requestEndDate, last.responseStartDate),
            (HTTPLogFields.responseMilliseconds, last.responseStartDate, last.responseEndDate)
        ]
        for case let (key, start?, end?) in spans {
            phases.append((key, NetworkLogger.milliseconds(end.timeIntervalSince(start))))
        }
    }

    func add(to metadata: inout [String: LogMetadataValue]) {
        if let networkProtocol {
            metadata[HTTPLogFields.networkProtocol] = .string(networkProtocol)
        }
        if let isReusedConnection {
            metadata[HTTPLogFields.reusedConnection] = .bool(isReusedConnection)
        }
        for phase in phases {
            metadata[phase.key] = .double(phase.milliseconds)
        }
    }
}

/// The per-task delegate of the logged calls. URLSession gives it the metrics instead of the session's delegate,
/// so it passes them on.
final class MetricsCollector: NSObject, URLSessionTaskDelegate, Sendable {
    private let state = OSAllocatedUnfairLock<HTTPMetrics?>(initialState: nil)

    var metrics: HTTPMetrics? {
        state.withLock { $0 }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didFinishCollecting metrics: URLSessionTaskMetrics) {
        let summary = HTTPMetrics(metrics)
        state.withLock { $0 = summary }
        (session.delegate as? any URLSessionTaskDelegate)?.urlSession?(session, task: task,
                                                                       didFinishCollecting: metrics)
    }
}

public extension URLSession {
    /// `data(for:)`, recorded in `logger` as one entry once the request completes or fails.
    ///
    /// The entry carries the caller's `LogContext` and call site. A failure is recorded, then rethrown. The
    /// session's delegate still receives the task's metrics. With bodies captured, the call returns once the
    /// body is redacted and written.
    func loggedData(for request: URLRequest, to logger: NetworkLogger, file: String = #fileID,
                    function: String = #function, line: Int = #line) async throws -> (Data, URLResponse) {
        try await logged(request: request, body: request.httpBody, to: logger, file: file, function: function,
                         line: line) { collector in
            try await self.data(for: request, delegate: collector)
        }
    }

    /// `upload(for:from:)`, recorded in `logger` as one entry once the request completes or fails.
    ///
    /// The entry carries the caller's `LogContext` and call site. A failure is recorded, then rethrown. The
    /// session's delegate still receives the task's metrics. With bodies captured, the call returns once the
    /// body is redacted and written.
    func loggedUpload(for request: URLRequest, from bodyData: Data, to logger: NetworkLogger,
                      file: String = #fileID, function: String = #function,
                      line: Int = #line) async throws -> (Data, URLResponse) {
        try await logged(request: request, body: bodyData, to: logger, file: file, function: function,
                         line: line) { collector in
            try await self.upload(for: request, from: bodyData, delegate: collector)
        }
    }

    private func logged(request: URLRequest, body: Data?, to logger: NetworkLogger, file: String,
                        function: String, line: Int,
                        perform: (MetricsCollector) async throws -> (Data, URLResponse)) async throws
        -> (Data, URLResponse) {
        let collector = MetricsCollector()
        let start = ContinuousClock.now
        var exchange = HTTPExchange(request: request, requestBody: body, requestBytes: body?.count ?? 0)
        do {
            let (data, response) = try await perform(collector)
            exchange.response = response
            exchange.responseBody = data
            exchange.responseBytes = data.count
            exchange.metrics = collector.metrics
            exchange.duration = Self.seconds(ContinuousClock.now - start)
            await logger.record(exchange, file: file, function: function, line: line)
            return (data, response)
        } catch {
            exchange.error = error
            exchange.metrics = collector.metrics
            exchange.duration = Self.seconds(ContinuousClock.now - start)
            await logger.record(exchange, file: file, function: function, line: line)
            throw error
        }
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
