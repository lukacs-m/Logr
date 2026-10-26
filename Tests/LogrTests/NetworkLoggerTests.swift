//
//  NetworkLoggerTests.swift
//  Logr
//

import Foundation
import Logr
@testable import LogrNetwork
import LogrTesting
@testable import LogrUI
import Network
import struct os.OSAllocatedUnfairLock
import Testing

// MARK: - Fixtures

/// Answers requests for `https://<id>.test/...` with the stub registered under `<id>`, so parallel tests never
/// share one.
final class StubProtocol: URLProtocol {
    struct Stub: Sendable {
        var status = 200
        var headers: [String: String] = [:]
        var body = Data()
        var error: URLError?
        /// Never answers, so the request ends only when cancelled.
        var hangs = false
    }

    private static let stubs = OSAllocatedUnfairLock<[String: Stub]>(initialState: [:])

    /// A session that reaches the stub, and the base URL to request.
    static func register(_ stub: Stub, delegate: (any URLSessionDelegate)? = nil,
                         additionalHeaders: [String: String] = [:]) -> (URLSession, String) {
        let id = UUID().uuidString.lowercased()
        stubs.withLock { $0[id] = stub }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        configuration.httpAdditionalHeaders = additionalHeaders
        return (URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil), "https://\(id).test")
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let id = request.url?.host?.components(separatedBy: ".").first ?? ""
        guard let stub = Self.stubs.withLock({ $0[id] }), !stub.hangs else { return }
        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1",
                                       headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// One-shot HTTP/1.1 server on a loopback port, for the timings a stub cannot produce.
final class LocalHTTPServer: Sendable {
    private let listener: NWListener
    let port: UInt16

    init(body: String) async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { _, _, _, _ in
                let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
                    + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
        let started = OSAllocatedUnfairLock(initialState: false)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready, .failed, .cancelled:
                    if !started.withLock({ defer { $0 = true }; return $0 }) { continuation.resume() }
                default:
                    break
                }
            }
            listener.start(queue: .global())
        }
        self.listener = listener
        port = try #require(listener.port?.rawValue)
    }

    deinit {
        listener.cancel()
    }
}

/// Counts the callbacks the proxy forwards, and reports completion.
final class ForwardingTarget: NSObject, URLSessionDataDelegate, Sendable {
    let events = OSAllocatedUnfairLock<[String]>(initialState: [])
    let completions: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    override init() {
        (completions, continuation) = AsyncStream.makeStream()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        events.withLock { $0.append("response") }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        events.withLock { $0.append("data") }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        events.withLock { $0.append("metrics") }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        events.withLock { $0.append("complete") }
        continuation.yield()
    }
}

// MARK: - Tests

@Suite("NetworkLogger")
struct NetworkLoggerTests {
    private let directory: TemporaryDirectory
    private let logr = LogR(cryptoService: LoggerCryptoService(store: InMemoryKeychainStore()),
                            configuration: LogrConfiguration(enabledLevels: Set(LogLevel.allCases),
                                                             mirrorToOSLog: false))
    private let crypto = LoggerCryptoService(store: InMemoryKeychainStore())

    init() throws {
        directory = try TemporaryDirectory()
    }

    private var bodyDirectory: URL {
        directory.url.appendingPathComponent("bodies")
    }

    private func network(_ configuration: NetworkLoggerConfiguration = NetworkLoggerConfiguration())
        -> NetworkLogger {
        NetworkLogger(logger: logr, configuration: configuration, cryptoService: crypto, bodyDirectory: bodyDirectory)
    }

    private var capturing: NetworkLogger {
        network(NetworkLoggerConfiguration(captureBodies: true))
    }

    private func entry() throws -> LogEntry {
        #expect(logr.recentLogs.count == 1)
        return try #require(logr.recentLogs.first)
    }

    private func storedFiles() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: bodyDirectory.path)) ?? []
    }

    private func body(of entry: LogEntry, in network: NetworkLogger) async throws -> NetworkBody? {
        guard case let .string(id)? = entry.metadata?[HTTPLogFields.bodyID] else { return nil }
        return try await network.body(id: id)
    }

    private func json(_ data: Data?) throws -> [String: Any] {
        let data = try #require(data)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func successfulRequestBecomesOneEntry() async throws {
        let payload = Data(#"{"id":1}"#.utf8)
        let (session, base) = StubProtocol.register(.init(headers: ["Content-Type": "application/json"],
                                                          body: payload))
        let (data, _) = try await LogContext.with(["requestID": "r-1"]) {
            try await session.loggedData(for: URLRequest(url: URL(string: base + "/users/42?page=2")!),
                                         to: network())
        }

        let entry = try entry()
        #expect(data == payload)
        #expect(entry.category == .http)
        #expect(entry.level == .info)
        #expect(entry.message.wholeMatch(of: /GET \/users\/42 → 200 \(\d+ ms\)/) != nil)
        #expect(entry.file == #fileID)
        let metadata = try #require(entry.metadata)
        #expect(metadata[HTTPLogFields.method] == "GET")
        #expect(metadata[HTTPLogFields.url] == .string(base + "/users/42?page=2"))
        #expect(metadata[HTTPLogFields.status] == 200)
        #expect(metadata[HTTPLogFields.requestBytes] == 0)
        #expect(metadata[HTTPLogFields.responseBytes] == .int(payload.count))
        #expect(metadata[HTTPLogFields.responseHeaders] == ["Content-Type": "application/json"])
        #expect(metadata["requestID"] == "r-1")
        guard case .double? = metadata[HTTPLogFields.durationMilliseconds] else {
            Issue.record("no duration")
            return
        }
        // A stub has no connection: no protocol, no phases, and no body without opting in.
        #expect(metadata[HTTPLogFields.networkProtocol] == nil)
        #expect(metadata[HTTPLogFields.connectMilliseconds] == nil)
        #expect(metadata[HTTPLogFields.bodyID] == nil)
        #expect(storedFiles().isEmpty)
    }

    @Test(arguments: [(200, LogLevel.info), (304, .info), (404, .warning), (503, .error)])
    func levelFollowsStatus(status: Int, level: LogLevel) async throws {
        let (session, base) = StubProtocol.register(.init(status: status))
        _ = try await session.loggedData(for: URLRequest(url: URL(string: base + "/x")!), to: network())
        #expect(try entry().level == level)
    }

    @Test func headersQueryAndUserInfoAreRedacted() async throws {
        let (session, base) = StubProtocol.register(.init(headers: ["Set-Cookie": "session=abc", "ETag": "v1"]))
        let url = base.replacingOccurrences(of: "https://", with: "https://zoe:pw@")
            + "/login?token=a1&page=2&Password=b2&q=a%20b#access_token=frag"
        var request = URLRequest(url: URL(string: url)!)
        request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        request.setValue("k", forHTTPHeaderField: "x-api-key")
        request.setValue("text/plain", forHTTPHeaderField: "Accept")

        _ = try await session.loggedData(for: request, to: network())

        let entry = try entry()
        let metadata = try #require(entry.metadata)
        #expect(metadata[HTTPLogFields.url]
            == .string(base + "/login?token=<private>&page=2&Password=<private>&q=a%20b"))
        #expect(metadata[HTTPLogFields.requestHeaders]
            == ["Authorization": "<private>", "x-api-key": "<private>", "Accept": "text/plain"])
        #expect(metadata[HTTPLogFields.responseHeaders] == ["Set-Cookie": "<private>", "Etag": "v1"])
        #expect(!entry.message.contains("token"))
    }

    @Test func transportErrorIsRecordedAndRethrown() async throws {
        let (session, base) = StubProtocol.register(.init(error: URLError(.timedOut)))
        await #expect(throws: URLError.self) {
            try await session.loggedData(for: URLRequest(url: URL(string: base + "/slow")!), to: network())
        }

        let entry = try entry()
        #expect(entry.level == .error)
        #expect(entry.message.hasPrefix("GET /slow → failed ("))
        #expect(entry.metadata?[HTTPLogFields.error] == "NSURLErrorDomain -1001")
        #expect(entry.metadata?[HTTPLogFields.status] == nil)
        #expect(entry.metadata?[HTTPLogFields.responseHeaders] == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationIsANotice() async throws {
        let (session, base) = StubProtocol.register(.init(hangs: true))
        let network = network()
        let task = Task {
            try await session.loggedData(for: URLRequest(url: URL(string: base + "/never")!), to: network)
        }
        task.cancel()
        _ = await task.result

        let entry = try entry()
        #expect(entry.level == .notice)
        #expect(entry.message.hasPrefix("GET /never → cancelled"))
    }

    @Test func bodiesAreRedactedAndKept() async throws {
        let response = #"{"user":{"name":"zoe","access_token":"t1"},"items":[{"Secret":"s"}],"n":1}"#
        let (session, base) = StubProtocol.register(.init(headers: ["Content-Type": "application/json; charset=utf-8"],
                                                          body: Data(response.utf8)))
        var request = URLRequest(url: URL(string: base + "/login")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"email":"zoe@example.com","password":"hunter2"}"#.utf8)
        let network = capturing

        _ = try await session.loggedData(for: request, to: network)

        let entry = try entry()
        #expect(entry.metadata?[HTTPLogFields.requestBytes] == .int(request.httpBody!.count))
        let body = try #require(try await body(of: entry, in: network))
        let sent = try json(body.request)
        #expect(sent["email"] as? String == "zoe@example.com")
        #expect(sent["password"] as? String == "<private>")
        let received = try json(body.response)
        #expect((received["user"] as? [String: Any])?["access_token"] as? String == "<private>")
        #expect((received["user"] as? [String: Any])?["name"] as? String == "zoe")
        #expect(((received["items"] as? [[String: Any]])?.first)?["Secret"] as? String == "<private>")
        #expect(!body.isRequestTruncated && !body.isResponseTruncated)
    }

    @Test func jsonEmbeddedInAStringIsRedacted() async throws {
        let response = #"{"data":"{\"user\":\"zoe\",\"password\":\"hunter2\"}","list":" [{\"token\":\"t\"}]","note":"{x"}"#
        let (session, base) = StubProtocol.register(.init(headers: ["Content-Type": "application/json"],
                                                          body: Data(response.utf8)))
        let network = capturing
        _ = try await session.loggedData(for: URLRequest(url: URL(string: base + "/echo")!), to: network)

        let received = try json(try await body(of: entry(), in: network)?.response)
        let data = try json(Data(try #require(received["data"] as? String).utf8))
        #expect(data["password"] as? String == "<private>")
        #expect(data["user"] as? String == "zoe")
        #expect(try #require(received["list"] as? String).contains("<private>"))
        #expect(received["note"] as? String == "{x")
    }

    @Test func jsonWithoutRedactedKeysIsKeptByteForByte() async throws {
        let response = Data("{ \"b\" : 1,\n \"a\" : [true] }".utf8)
        let (session, base) = StubProtocol.register(.init(headers: ["Content-Type": "application/problem+json"],
                                                          body: response))
        let network = capturing
        _ = try await session.loggedData(for: URLRequest(url: URL(string: base + "/x")!), to: network)

        #expect(try await body(of: entry(), in: network)?.response == response)
    }

    @Test func formBodyIsRedacted() async throws {
        let (session, base) = StubProtocol.register(.init())
        var request = URLRequest(url: URL(string: base + "/login")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let network = capturing

        _ = try await session.loggedUpload(for: request, from: Data("user=zoe&pass%77ord=x;tail&token=y".utf8),
                                           to: network)

        let entry = try entry()
        #expect(entry.metadata?[HTTPLogFields.requestBytes] == 34)
        let body = try #require(try await body(of: entry, in: network))
        #expect(body.request == Data("user=zoe&pass%77ord=<private>&token=<private>".utf8))
        #expect(body.response == nil)
    }

    @Test(arguments: [
        ("text/plain", "plain text", true),
        ("application/xml", "<a/>", true),
        ("image/png", "\u{89}PNG", false),
        (nil, "untyped", false),
        ("application/json", "{not json", false)
    ] as [(String?, String, Bool)])
    func onlyTextualRedactableBodiesAreKept(contentType: String?, text: String, isKept: Bool) async throws {
        let (session, base) = StubProtocol.register(.init(headers: contentType.map { ["Content-Type": $0] } ?? [:],
                                                          body: Data(text.utf8)))
        let network = capturing
        _ = try await session.loggedData(for: URLRequest(url: URL(string: base + "/x")!), to: network)

        let body = try await body(of: entry(), in: network)
        #expect(body?.response == (isKept ? Data(text.utf8) : nil))
        #expect(storedFiles().count == (isKept ? 1 : 0))
    }

    @Test func longBodiesAreCutAfterRedaction() async throws {
        let response = Data(repeating: UInt8(ascii: "a"), count: 100 * 1024)
        let (session, base) = StubProtocol.register(.init(headers: ["Content-Type": "text/plain"], body: response))
        let network = capturing
        _ = try await session.loggedData(for: URLRequest(url: URL(string: base + "/big")!), to: network)

        let entry = try entry()
        let body = try #require(try await body(of: entry, in: network))
        #expect(body.response?.count == 64 * 1024)
        #expect(body.isResponseTruncated)
        #expect(entry.metadata?[HTTPLogFields.responseBytes] == .int(response.count))
    }

    @Test(.timeLimit(.minutes(1)))
    func ringKeepsTheNewestHundred() async throws {
        let (session, base) = StubProtocol.register(.init(headers: ["Content-Type": "text/plain"],
                                                          body: Data("ok".utf8)))
        let network = capturing
        for index in 0..<101 {
            _ = try await session.loggedData(for: URLRequest(url: URL(string: base + "/\(index)")!), to: network)
        }

        let ids = logr.recentLogs.reversed().compactMap { entry -> String? in
            guard case let .string(id)? = entry.metadata?[HTTPLogFields.bodyID] else { return nil }
            return id
        }
        #expect(ids.count == 101)
        #expect(storedFiles().count == 100)
        #expect(try await network.body(id: ids[0]) == nil)
        for id in ids.dropFirst() {
            #expect(try await network.body(id: id)?.response == Data("ok".utf8))
        }
    }

    @Test func bodiesAreEncryptedOnDisk() async throws {
        let marker = "plain-marker-0123456789"
        let (session, base) = StubProtocol.register(.init(headers: ["Content-Type": "text/plain"],
                                                          body: Data(marker.utf8)))
        _ = try await session.loggedData(for: URLRequest(url: URL(string: base + "/x")!), to: capturing)

        let file = try #require(storedFiles().first)
        let bytes = try Data(contentsOf: bodyDirectory.appendingPathComponent(file))
        #expect(bytes.range(of: Data(marker.utf8)) == nil)
        #expect(bytes.range(of: Data(Data(marker.utf8).base64EncodedString().utf8)) == nil)
        #expect(try bodyDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func clearBodiesDeletesEveryBody() async throws {
        let (session, base) = StubProtocol.register(.init(headers: ["Content-Type": "text/plain"],
                                                          body: Data("ok".utf8)))
        let network = capturing
        _ = try await session.loggedData(for: URLRequest(url: URL(string: base + "/x")!), to: network)
        #expect(try await body(of: entry(), in: network) != nil)

        try await network.clearBodies()

        #expect(try await body(of: entry(), in: network) == nil)
        #expect(storedFiles().isEmpty)
    }

    @Test(arguments: ["", "../../etc/passwd", "00000000000000000001-../x", "abc",
                      "0000000000000000001-6F9619FF-8B86-D011-B42D-00C04FC964FF"])
    func malformedIDsResolveToNothing(id: String) async throws {
        #expect(try await capturing.body(id: id) == nil)
    }

    @Test func clearBodiesWithNothingStoredSucceeds() async throws {
        try await capturing.clearBodies()
        #expect(storedFiles().isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func realConnectionsRecordProtocolAndPhases() async throws {
        let server = try await LocalHTTPServer(body: #"{"ok":true}"#)
        let url = URL(string: "http://127.0.0.1:\(server.port)/status")!
        _ = try await URLSession(configuration: .ephemeral).loggedData(for: URLRequest(url: url), to: network())

        let metadata = try #require(try entry().metadata)
        #expect(metadata[HTTPLogFields.networkProtocol] == "http/1.1")
        #expect(metadata[HTTPLogFields.reusedConnection] == false)
        for key in [HTTPLogFields.connectMilliseconds, HTTPLogFields.requestMilliseconds,
                    HTTPLogFields.waitMilliseconds, HTTPLogFields.responseMilliseconds,
                    HTTPLogFields.durationMilliseconds] {
            guard case let .double(value)? = metadata[key] else {
                Issue.record("\(key) missing")
                continue
            }
            #expect(value >= 0)
        }
        #expect(metadata[HTTPLogFields.secureConnectionMilliseconds] == nil)
    }

    // MARK: Proxy delegate

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, *)
    @Test(.timeLimit(.minutes(1)))
    func proxyRecordsDelegateTasksAndForwardsEverything() async throws {
        let target = ForwardingTarget()
        let network = capturing
        let proxy = LogrURLSessionProxyDelegate(logger: network, forwardingTo: target)
        let (session, base) = StubProtocol.register(.init(status: 201, headers: ["Content-Type": "application/json"],
                                                          body: Data(#"{"token":"t","id":7}"#.utf8)),
                                                    delegate: proxy)

        session.dataTask(with: URL(string: base + "/items")!).resume()
        var completions = target.completions.makeAsyncIterator()
        _ = await completions.next()
        _ = await Observations { logr.recentLogs }.first { !$0.isEmpty }

        // `response` is not implemented by the proxy: it reaches the target through forwarding.
        #expect(target.events.withLock { $0 } == ["response", "data", "metrics", "complete"])
        let entry = try entry()
        #expect(entry.message.hasPrefix("GET /items → 201"))
        #expect(entry.metadata?[HTTPLogFields.responseBytes] == 20)
        let received = try json(try await body(of: entry, in: network)?.response)
        #expect(received["token"] as? String == "<private>")
        #expect(received["id"] as? Int == 7)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, *)
    @Test(.timeLimit(.minutes(1)))
    func proxyRecordsAsyncAndCompletionHandlerTasks() async throws {
        let proxy = LogrURLSessionProxyDelegate(logger: capturing)
        let (session, base) = StubProtocol.register(.init(status: 404, headers: ["Content-Type": "text/plain"],
                                                          body: Data("missing".utf8)),
                                                    delegate: proxy)

        _ = try await session.data(from: URL(string: base + "/async")!)
        await withCheckedContinuation { continuation in
            session.dataTask(with: URL(string: base + "/handler")!) { _, _, _ in continuation.resume() }.resume()
        }
        let logs = await Observations { logr.recentLogs }.first { $0.count == 2 }

        let messages = Set(try #require(logs).map(\.message).map { $0.prefix { $0 != "(" } })
        #expect(messages == ["GET /async → 404 ", "GET /handler → 404 "])
        // URLSession keeps the data of these tasks from the session delegate: no body.
        #expect(try #require(logs).allSatisfy { $0.metadata?[HTTPLogFields.bodyID] == nil && $0.level == .warning })
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, *)
    @Test(.timeLimit(.minutes(1)))
    func proxyDoesNotKeepAJSONBodyItCut() async throws {
        let target = ForwardingTarget()
        let proxy = LogrURLSessionProxyDelegate(logger: network(NetworkLoggerConfiguration(captureBodies: true,
                                                                                             maxBodyBytes: 8)),
                                                forwardingTo: target)
        let (session, base) = StubProtocol.register(.init(headers: ["Content-Type": "application/json"],
                                                          body: Data(#"{"id":7}{"token":"secret"}"#.utf8)),
                                                    delegate: proxy)

        session.dataTask(with: URL(string: base + "/items")!).resume()
        var completions = target.completions.makeAsyncIterator()
        _ = await completions.next()
        _ = await Observations { logr.recentLogs }.first { !$0.isEmpty }

        #expect(try entry().metadata?[HTTPLogFields.bodyID] == nil)
        #expect(try entry().metadata?[HTTPLogFields.responseBytes] == 26)
        #expect(storedFiles().isEmpty)
    }

    // MARK: Review regressions

    @Test(arguments: [300, 2_000])
    func deeplyNestedJSONIsNotKeptAndDoesNotCrash(depth: Int) async throws {
        // Nested arrays carrying a string that is itself nested JSON: each level used to recurse once more.
        let inner = String(repeating: "[", count: depth) + "1" + String(repeating: "]", count: depth)
        let escaped = inner.replacingOccurrences(of: "\"", with: "\\\"")
        let outer = String(repeating: "[", count: 400) + "\"\(escaped)\"" + String(repeating: "]", count: 400)
        let (session, base) = StubProtocol.register(.init(headers: ["Content-Type": "application/json"],
                                                          body: Data(outer.utf8)))
        let network = capturing
        _ = try await session.loggedData(for: URLRequest(url: URL(string: base + "/deep")!), to: network)

        #expect(try entry().metadata?[HTTPLogFields.bodyID] == nil)
        #expect(storedFiles().isEmpty)
    }

    @Test func jsonTooLargeToRedactIsNotKept() async throws {
        let filler = String(repeating: "a", count: 1 << 20)
        let response = Data(#"{"token":"t","filler":"\#(filler)"}"#.utf8)
        let (session, base) = StubProtocol.register(.init(headers: ["Content-Type": "application/json"],
                                                          body: response))
        _ = try await session.loggedData(for: URLRequest(url: URL(string: base + "/big")!), to: capturing)

        #expect(try entry().metadata?[HTTPLogFields.bodyID] == nil)
        #expect(storedFiles().isEmpty)
    }

    @Test func sessionDelegateStillReceivesMetrics() async throws {
        let target = ForwardingTarget()
        let (session, base) = StubProtocol.register(.init(), delegate: target)
        _ = try await session.loggedData(for: URLRequest(url: URL(string: base + "/x")!), to: network())
        #expect(target.events.withLock { $0 }.contains("metrics"))
    }

    @Test func filteredEntriesKeepNoBodyAndEvictNothing() async throws {
        let logr = LogR(cryptoService: LoggerCryptoService(store: InMemoryKeychainStore()),
                        configuration: LogrConfiguration(categoryLevelOverrides: [.http: .warning],
                                                         mirrorToOSLog: false))
        let network = NetworkLogger(logger: logr,
                                    configuration: NetworkLoggerConfiguration(captureBodies: true, maxStoredBodies: 1),
                                    cryptoService: crypto, bodyDirectory: bodyDirectory)
        let (failing, failingBase) = StubProtocol.register(.init(status: 500, headers: ["Content-Type": "text/plain"],
                                                                 body: Data("kept".utf8)))
        let (ok, okBase) = StubProtocol.register(.init(headers: ["Content-Type": "text/plain"],
                                                       body: Data("filtered".utf8)))

        _ = try await failing.loggedData(for: URLRequest(url: URL(string: failingBase + "/a")!), to: network)
        _ = try await ok.loggedData(for: URLRequest(url: URL(string: okBase + "/b")!), to: network)

        let logged = try #require(logr.recentLogs.first)
        #expect(logr.recentLogs.count == 1)
        #expect(try await body(of: logged, in: network)?.response == Data("kept".utf8))
        #expect(storedFiles().count == 1)
    }

    @Test func bodiesWrittenAfterAClockStepBackAreKept() async throws {
        try FileManager.default.createDirectory(at: bodyDirectory, withIntermediateDirectories: true)
        let future = "18000000000000000000-" + UUID().uuidString
        try Data().write(to: bodyDirectory.appendingPathComponent(future))
        let (session, base) = StubProtocol.register(.init(headers: ["Content-Type": "text/plain"],
                                                          body: Data("now".utf8)))
        let network = network(NetworkLoggerConfiguration(captureBodies: true, maxStoredBodies: 1))
        _ = try await session.loggedData(for: URLRequest(url: URL(string: base + "/x")!), to: network)

        #expect(try await body(of: entry(), in: network)?.response == Data("now".utf8))
        #expect(!storedFiles().contains(future))
    }

    /// 500 nested objects, and 120 arrays around a string holding 400 nested objects: Foundation's parser
    /// recursing that deep overflows a cooperative thread's stack.
    private static let tooDeepBodies: [String] = {
        let objects: (Int, String) -> String = { count, quote in
            String(repeating: "{\(quote)a\(quote):", count: count) + "1" + String(repeating: "}", count: count)
        }
        let embedded: String = String(repeating: "[", count: 120) + "\"" + objects(400, "\\\"") + "\""
            + String(repeating: "]", count: 120)
        return [objects(500, "\""), embedded]
    }()

    @Test(arguments: tooDeepBodies)
    func jsonNestedBeyondTheBudgetIsRejectedBeforeParsing(body: String) async throws {
        let (session, base) = StubProtocol.register(.init(headers: ["Content-Type": "application/json"],
                                                          body: Data(body.utf8)))
        _ = try await session.loggedData(for: URLRequest(url: URL(string: base + "/deep")!), to: capturing)

        #expect(try entry().metadata?[HTTPLogFields.bodyID] == nil)
        #expect(storedFiles().isEmpty)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, *)
    @Test(.timeLimit(.minutes(1)))
    func loggedDataThroughAProxySessionIsRecordedOnce() async throws {
        let network = capturing
        let (session, base) = StubProtocol.register(.init(), delegate: LogrURLSessionProxyDelegate(logger: network))
        _ = try await session.loggedData(for: URLRequest(url: URL(string: base + "/once")!), to: network)
        // The proxy would record on its own task; give it the same chance a real one has.
        _ = try await session.data(from: URL(string: base + "/marker")!)
        _ = await Observations { logr.recentLogs }.first { $0.contains { $0.message.hasPrefix("GET /marker") } }

        #expect(logr.recentLogs.filter { $0.message.hasPrefix("GET /once") }.count == 1)
    }

    @Test func aPendingBodyNeitherCountsNorGetsPruned() async throws {
        let store = NetworkBodyStore(directory: bodyDirectory, crypto: crypto, limit: 1)
        let body = NetworkBody(request: nil, response: Data("k".utf8), isRequestTruncated: false,
                               isResponseTruncated: false)
        let kept = try #require(await store.write(body))
        let filtered = try #require(await store.write(body))
        await store.commit(id: kept)
        await store.remove(id: filtered)

        #expect(try await store.body(id: kept) != nil)
        #expect(storedFiles() == [kept])
    }

    /// The parser reads UTF-16 and UTF-32 too; a byte-wise scan of those must not let a deep document through.
    @Test func jsonInAnotherEncodingIsNotKeptAndDoesNotCrash() async throws {
        let document = #"["\"","# + String(repeating: #"{"a":"#, count: 600) + "1"
            + String(repeating: "}", count: 600) + "]"
        let utf16 = try #require(document.data(using: .utf16LittleEndian))
        let interleaved = document.map { "\($0)\u{0}" }.joined()
        let embedding = try JSONSerialization.data(withJSONObject: ["a": interleaved, "token": "x"])
        let network = capturing
        for body in [utf16, embedding] {
            let (session, base) = StubProtocol.register(.init(headers: ["Content-Type": "application/json"],
                                                              body: body))
            _ = try await session.loggedData(for: URLRequest(url: URL(string: base + "/wide")!), to: network)
        }

        #expect(logr.recentLogs.count == 2)
        #expect(logr.recentLogs.allSatisfy { $0.metadata?[HTTPLogFields.bodyID] == nil })
        #expect(storedFiles().isEmpty)
    }

    @Test func semicolonSeparatedPairsAreRedacted() async throws {
        let (session, base) = StubProtocol.register(.init())
        _ = try await session.loggedData(for: URLRequest(url: URL(string: base + "/cb?a=1;token=secret&b=2&password=abc;def")!),
                                         to: network())
        #expect(try entry().metadata?[HTTPLogFields.url] == .string(base + "/cb?a=1;token=<private>&b=2&password=<private>"))
    }

    @Test func headersTheSessionAddsAreRecordedAndRedacted() async throws {
        let (session, base) = StubProtocol.register(.init(), additionalHeaders: ["Authorization": "Bearer config",
                                                                                 "X-Auth-Token": "cfg",
                                                                                 "X-Extra": "1"])
        var request = URLRequest(url: URL(string: base + "/x")!)
        request.setValue("own", forHTTPHeaderField: "X-Own")
        _ = try await session.loggedData(for: request, to: network())

        #expect(try entry().metadata?[HTTPLogFields.requestHeaders]
            == ["Authorization": "<private>", "X-Auth-Token": "<private>", "X-Extra": "1", "X-Own": "own"])
    }

    @Test(arguments: [
        (101, nil, LogLevel.info, HTTPStatusClass.informational),
        (204, nil, .info, .success),
        (nil, "NSURLErrorDomain -999", .notice, .cancelled),
        (nil, "NSURLErrorDomain -1001", .error, .failed),
        (0, nil, .info, .failed)
    ] as [(Int?, String?, LogLevel, HTTPStatusClass)])
    @MainActor
    func statusClassesMatchTheOutcome(status: Int?, error: String?, level: LogLevel, expected: HTTPStatusClass) {
        var metadata: [String: LogMetadataValue] = [HTTPLogFields.method: "GET", HTTPLogFields.url: "https://a.test/"]
        metadata[HTTPLogFields.status] = status.map { .int($0) }
        metadata[HTTPLogFields.error] = error.map { .string($0) }
        let entry = LogEntry(level: level, category: .http, subsystem: "test", message: "GET /", metadata: metadata)
        #expect(NetworkRequest(entry)?.statusClass == expected)
    }

    @Test func urlHeadersAreRedactedLikeTheURL() async throws {
        let (session, base) = StubProtocol.register(.init(status: 302, headers: [
            "Location": "/cb?access_token=t1&state=1#id_token=t2",
            "Content-Location": "https://u:p@other.test/doc?token=t3"
        ]))
        var request = URLRequest(url: URL(string: base + "/authorize")!)
        request.setValue("https://app.test/page?api_key=k", forHTTPHeaderField: "Referer")
        _ = try await session.loggedData(for: request, to: network())

        let metadata = try #require(entry().metadata)
        #expect(metadata[HTTPLogFields.responseHeaders] == [
            "Location": .string(base + "/cb?access_token=<private>&state=1"),
            "Content-Location": "https://other.test/doc?token=<private>"
        ])
        #expect(metadata[HTTPLogFields.requestHeaders] == ["Referer": "https://app.test/page?api_key=<private>"])
    }

    @Test func bracketedAndWidenedKeysAreRedacted() async throws {
        let (session, base) = StubProtocol.register(.init())
        let query = "user%5Bpassword%5D=a&client_secret=b&X-Amz-Signature=c&user%5Bname%5D=zoe"
        _ = try await session.loggedData(for: URLRequest(url: URL(string: base + "/x?" + query)!), to: network())
        let url = try entry().metadata?[HTTPLogFields.url]
        #expect(url == .string(base + "/x?user%5Bpassword%5D=<private>"
                + "&client_secret=<private>&X-Amz-Signature=<private>&user%5Bname%5D=zoe"))
    }
}
