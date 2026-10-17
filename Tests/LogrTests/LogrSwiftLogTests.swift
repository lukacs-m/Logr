import Logging
import Logr
import LogrSwiftLog
import Foundation
import LogrTesting
import class OSLog.OSLogEntryLog
import class OSLog.OSLogStore
import struct os.OSAllocatedUnfairLock
import Testing

@Suite("LogrLogHandler")
struct LogrLogHandlerTests {
    private let logr = LogR(cryptoService: LoggerCryptoService(store: InMemoryKeychainStore()),
                            configuration: LogrConfiguration(enabledLevels: Set(LogLevel.allCases),
                                                             mirrorToOSLog: false,
                                                             storesPrivateValues: false))

    private func swiftLogger(_ label: String = "checkout",
                             configure: (inout LogrLogHandler) -> Void = { _ in }) -> Logger {
        Logger(label: label) { label in
            var handler = LogrLogHandler(label: label, logger: logr, metadataProvider: nil)
            configure(&handler)
            return handler
        }
    }

    @Test(arguments: [
        (Logger.Level.trace, LogLevel.debug),
        (.debug, .debug),
        (.info, .info),
        (.notice, .notice),
        (.warning, .warning),
        (.error, .error),
        (.critical, .fault)
    ])
    func levelsMap(swiftLogLevel: Logger.Level, expected: LogLevel) throws {
        var logger = swiftLogger()
        logger.logLevel = .trace
        logger.log(level: swiftLogLevel, "message")
        #expect(try #require(logr.recentLogs.first).level == expected)
    }

    @Test func entryKeepsTheMessageCallSiteAndLabelAsCategory() throws {
        let line = #line + 1
        swiftLogger().info("Paid \(42) with card")

        let entry = try #require(logr.recentLogs.first)
        #expect(entry.message == "Paid 42 with card")
        #expect(entry.privateRanges.isEmpty)
        #expect(entry.category == "checkout")
        #expect(entry.file == #fileID)
        #expect(entry.function == #function)
        #expect(entry.line == line)
        #expect(entry.metadata == nil)
    }

    @Test func categoryAndMessagePrivacyAreConfigurable() throws {
        let logger = Logger(label: "com.example.checkout") { label in
            LogrLogHandler(label: label, logger: logr, category: .payment, messagePrivacy: .private,
                           metadataProvider: nil)
        }
        logger.info("card 4242")

        let entry = try #require(logr.recentLogs.first)
        #expect(entry.category == .payment)
        #expect(entry.message == "<private>")
    }

    @Test func anEmptyLabelLogsAsSwiftLog() throws {
        swiftLogger("").info("unbound")
        #expect(try #require(logr.recentLogs.first).category == "swift-log")
    }

    @Test func handlerLogLevelFiltersBeforeLogr() {
        var logger = swiftLogger()
        logger.debug("dropped by the default level")
        logger.info("kept by default")
        logger.logLevel = .warning
        logger.info("dropped")
        logger.warning("kept")
        #expect(logr.recentLogs.map(\.message) == ["kept", "kept by default"])
    }

    @Test func eventsLogrFiltersOutNeverBuildTheirMetadata() {
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let filtering = LogR(cryptoService: LoggerCryptoService(store: InMemoryKeychainStore()),
                             configuration: LogrConfiguration(enabledLevels: [.error], mirrorToOSLog: false))
        let provider = Logger.MetadataProvider {
            calls.withLock { $0 += 1 }
            return ["k": "v"]
        }
        let logger = Logger(label: "checkout") { label in
            LogrLogHandler(label: label, logger: filtering, metadataProvider: provider)
        }
        logger.info("filtered by Logr")
        #expect(calls.withLock { $0 } == 0)
        logger.error("kept")
        #expect(calls.withLock { $0 } == 1)
        #expect(filtering.recentLogs.map(\.metadata) == [["k": "v"]])
    }

    @Test func metadataMergesHandlerThenProviderThenEvent() throws {
        let provider = Logger.MetadataProvider { ["provided": "p", "shared": "provider", "override": "provider"] }
        var logger = Logger(label: "checkout") { label in
            LogrLogHandler(label: label, logger: logr, metadataProvider: provider)
        }
        logger[metadataKey: "handler"] = "h"
        logger[metadataKey: "shared"] = "handler"
        logger.info("merged", metadata: [
            "override": "event",
            "nested": ["list": ["a", .stringConvertible(1)], "flag": .stringConvertible(true)]
        ])

        let metadata = try #require(logr.recentLogs.first?.metadata)
        #expect(metadata == [
            "handler": "h",
            "provided": "p",
            "shared": "provider",
            "override": "event",
            "nested": ["list": ["a", "1"], "flag": "true"]
        ])
    }

    @Test func onlyAnExplicitSourceGoesIntoMetadata() throws {
        swiftLogger().info("explicit source", source: "Payments")
        swiftLogger().info("implicit source")

        let entries = logr.recentLogs
        #expect(entries.first?.metadata == nil)
        #expect(entries.last?.metadata == ["source": "Payments"])
    }

    @Test(arguments: [false, true])
    func theErrorIsAPrivateValueOfTheMessage(storesPrivateValues: Bool) async throws {
        struct PaymentDeclined: Error {}
        let logr = LogR(cryptoService: LoggerCryptoService(store: InMemoryKeychainStore()),
                        configuration: LogrConfiguration(mirrorToOSLog: false,
                                                         storesPrivateValues: storesPrivateValues))
        let logger = Logger(label: "checkout") { label in
            LogrLogHandler(label: label, logger: logr, metadataProvider: nil)
        }
        logger.error("Payment failed", error: PaymentDeclined(), metadata: ["error": "caller's"])

        let entry = try #require(logr.recentLogs.first)
        #expect(entry.message == (storesPrivateValues ? "Payment failed PaymentDeclined()" : "Payment failed <private>"))
        #expect(entry.metadata == ["error": "caller's"])
        let export = try await logr.exportLogs(format: .txt, includingPrivateValues: false)
        #expect(!String(decoding: export, as: UTF8.self).contains("PaymentDeclined"))
    }

    @Test func sourceReplacesTheCallersKey() {
        swiftLogger().info("clash", metadata: ["source": "push"], source: "Net")
        #expect(logr.recentLogs.first?.metadata == ["source": "Net"])
    }

    @Test(arguments: ["main.swift", ""])
    func aFileWithoutModuleAddsNoSource(file: String) {
        let handler = LogrLogHandler(label: "checkout", logger: logr, metadataProvider: nil)
        handler.log(event: LogEvent(level: .info, message: "no module", metadata: nil, source: nil, file: file,
                                    function: "f", line: 1))
        #expect(logr.recentLogs.first?.metadata == nil)
    }

    @Test func aLineBeyondIntIsClamped() {
        let handler = LogrLogHandler(label: "checkout", logger: logr, metadataProvider: nil)
        handler.log(event: LogEvent(level: .info, message: "far", metadata: nil, source: nil,
                                    file: "LogrTests/x.swift", function: "f", line: .max))
        #expect(logr.recentLogs.first?.line == .max)
    }

    @Test func sensitivityAttributeIsHonoured() throws {
        swiftLogger().info("signed in", metadata: [
            "email": .attributed("zoe@example.com", attributes: [LogrSensitivity.private]),
            "token": .attributed("hunter2", attributes: [LogrSensitivity.sensitive]),
            "plan": .attributed("pro", attributes: [LogrSensitivity.public]),
            "nested": ["email": .attributed("zoe@example.com", attributes: [LogrSensitivity.private])],
            "untagged": "visible"
        ])

        let metadata = try #require(logr.recentLogs.first?.metadata)
        #expect(metadata == [
            "email": "<private>",
            "token": "<sensitive>",
            "plan": "pro",
            "nested": ["email": "<private>"],
            "untagged": "visible"
        ])
    }

    @Test func taskLocalLoggerMetadataIsKept() async throws {
        await withLogger(swiftLogger()) { _ in
            await withLogger(mergingMetadata: ["request": "1"]) { logger in
                await Task.yield()
                logger.info("inside")
                Logger.current.info("current")
            }
        }

        #expect(logr.recentLogs.map(\.message) == ["current", "inside"])
        #expect(logr.recentLogs.map(\.metadata) == [["request": "1"], ["request": "1"]])
    }

    @Test func logContextGoesUnderTheEventMetadata() throws {
        LogContext.with(["request": "1", "screen": "cart"]) {
            swiftLogger().info("inside", metadata: ["screen": "pay"])
        }
        #expect(logr.recentLogs.first?.metadata == ["request": "1", "screen": "pay"])
    }

    @Test func bridgedEventsReachTheOSLogMirror() throws {
        let subsystem = "com.logr.tests.\(UUID().uuidString)"
        let logr = LogR(cryptoService: LoggerCryptoService(store: InMemoryKeychainStore()),
                        configuration: LogrConfiguration(subsystem: subsystem, logVerbosity: .normal,
                                                         storesPrivateValues: false))
        let start = Date()
        let logger = Logger(label: "com.example.http-client") { label in
            LogrLogHandler(label: label, logger: logr, metadataProvider: nil)
        }
        logger.error("Payment failed", error: CancellationError())
        logger.error("Payment failed again")

        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let mirrored = try store.getEntries(at: store.position(date: start),
                                            matching: NSPredicate(format: "subsystem == %@", subsystem))
            .compactMap { $0 as? OSLogEntryLog }
        #expect(mirrored.map(\.category) == ["com.example.http-client", "com.example.http-client"])
        // The trailing private argument reads in clear under a debugger or with private data logging on.
        #expect(mirrored.first?.composedMessage.hasPrefix("Payment failed <private> ") == true)
        #expect(mirrored.last?.composedMessage == "Payment failed again")
    }

    @Test func worksAlongsideAStreamHandler() throws {
        let stream = CapturingStream()
        let logger = Logger(label: "checkout") { label in
            MultiplexLogHandler([
                LogrLogHandler(label: label, logger: logr, metadataProvider: nil),
                StreamLogHandler(label: label, stream: stream, metadataProvider: nil)
            ])
        }
        logger.notice("both", metadata: ["k": "v"])

        let entry = try #require(logr.recentLogs.first)
        #expect(entry.message == "both")
        #expect(entry.metadata == ["k": "v"])
        #expect(stream.text.contains("notice checkout: k=v [LogrTests] both"))
    }
}

private final class CapturingStream: TextOutputStream, Sendable {
    private let buffer = OSAllocatedUnfairLock(initialState: "")

    var text: String {
        buffer.withLock { $0 }
    }

    func write(_ string: String) {
        buffer.withLock { $0 += string }
    }
}
