//
//  LogrURLSessionProxyDelegate.swift
//  LogrNetwork
//

import Foundation
import os

/// A session delegate that records every task of its session in a ``NetworkLogger`` and forwards every callback
/// to your own delegate.
///
/// For apps that own their session delegate: create the session with this one and pass yours as `target`.
///
/// ```swift
/// let delegate = LogrURLSessionProxyDelegate(logger: network, forwardingTo: myDelegate)
/// let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
/// ```
///
/// A task is recorded when its metrics arrive, whichever way it was started: with `async` methods, a completion
/// handler or delegate callbacks. URLSession hands data to the session delegate only for tasks without a
/// completion handler and outside the `async` methods, so bodies are captured for those tasks only, and of a
/// response no more than ``NetworkLoggerConfiguration/maxBodyBytes`` (a longer JSON or form response cannot be
/// redacted, so it is not kept). Request bodies are captured from `httpBody`, not from upload files or streams.
///
/// Background sessions are not supported. A task given its own delegate (`data(for:delegate:)`) sends its
/// metrics there, so it is not recorded here; a `loggedData` or `loggedUpload` task is recorded once, by that
/// call. Entries carry the call site of this initializer and no `LogContext`.
public final class LogrURLSessionProxyDelegate: NSObject, URLSessionDataDelegate, Sendable {
    private let logger: NetworkLogger
    private let target: (any URLSessionDelegate)?
    private let file: String
    private let function: String
    private let line: Int
    private let bodies = OSAllocatedUnfairLock<[ObjectIdentifier: ReceivedBody]>(initialState: [:])

    private struct ReceivedBody {
        var data = Data()
        var count = 0
    }

    /// Creates a delegate that records tasks in `logger` and forwards every callback to `target`.
    ///
    /// - Parameters:
    ///   - logger: Where tasks are recorded.
    ///   - target: Your session delegate, if any. It receives every callback, including those this delegate
    ///     handles.
    ///   - file: The call site the entries carry (automatically captured).
    ///   - function: The call site the entries carry (automatically captured).
    ///   - line: The call site the entries carry (automatically captured).
    public init(logger: NetworkLogger, forwardingTo target: (any URLSessionDelegate)? = nil,
                file: String = #fileID, function: String = #function, line: Int = #line) {
        self.logger = logger
        self.target = target
        self.file = file
        self.function = function
        self.line = line
    }

    override public func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || target?.responds(to: aSelector) == true
    }

    override public func forwardingTarget(for aSelector: Selector!) -> Any? {
        target?.responds(to: aSelector) == true ? target : super.forwardingTarget(for: aSelector)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let contentType = (dataTask.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")
        if logger.configuration.captureBodies, BodyKind(contentType: contentType) != nil {
            let limit = logger.configuration.maxBodyBytes
            bodies.withLock { bodies in
                var body = bodies[ObjectIdentifier(dataTask), default: ReceivedBody()]
                body.data.append(data.prefix(max(0, limit - body.data.count)))
                body.count += data.count
                bodies[ObjectIdentifier(dataTask)] = body
            }
        }
        (target as? any URLSessionDataDelegate)?.urlSession?(session, dataTask: dataTask, didReceive: data)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask,
                           didFinishCollecting metrics: URLSessionTaskMetrics) {
        let body = bodies.withLock { $0.removeValue(forKey: ObjectIdentifier(task)) }
        // `loggedData` records its own tasks and passes their metrics on to the session's delegate.
        if task.delegate is MetricsCollector {
            (target as? any URLSessionTaskDelegate)?.urlSession?(session, task: task, didFinishCollecting: metrics)
            return
        }
        let request = task.originalRequest
        var exchange = HTTPExchange(request: request, requestBody: request?.httpBody,
                                    requestBytes: max(Int(task.countOfBytesSent), request?.httpBody?.count ?? 0))
        // Every probed task exposed its response or error by now; the transaction is the fallback.
        exchange.response = task.response ?? metrics.transactionMetrics.last?.response
        exchange.error = task.error
        if exchange.response != nil {
            exchange.responseBody = body?.data
            exchange.isResponseBodyComplete = (body?.count ?? 0) == (body?.data.count ?? 0)
            exchange.responseBytes = max(Int(task.countOfBytesReceived), body?.count ?? 0)
        }
        exchange.metrics = HTTPMetrics(metrics)
        let logger = logger, file = file, function = function, line = line
        Task {
            await logger.record(exchange, file: file, function: function, line: line)
        }
        (target as? any URLSessionTaskDelegate)?.urlSession?(session, task: task, didFinishCollecting: metrics)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        // Metrics come first; this only drops data of a task whose metrics never came.
        bodies.withLock { $0[ObjectIdentifier(task)] = nil }
        (target as? any URLSessionTaskDelegate)?.urlSession?(session, task: task, didCompleteWithError: error)
    }
}
