import CryptoKit
import Foundation
@testable import Logr
import LogrTesting
import OSLog
import Testing

@Suite("Private values in entries and configuration")
struct PrivateEntryTests {
    @Test func privateRangesRoundTrip() throws {
        let entry = LogEntry(level: .info, category: .user, subsystem: "t", message: "user Zoë", privateRanges: [5..<9])
        let decoded = try JSONDecoder().decode(LogEntry.self, from: JSONEncoder().encode(entry))
        #expect(decoded == entry)
        #expect(decoded.privateRanges == [5..<9])
    }

    @Test func entriesWithoutPrivateValuesDoNotEncodeTheField() throws {
        let entry = LogEntry(level: .info, category: .user, subsystem: "t", message: "hello")
        let json = try #require(String(data: JSONEncoder().encode(entry), encoding: .utf8))
        #expect(!json.contains("privateRanges"))
        #expect(try JSONDecoder().decode(LogEntry.self, from: Data(json.utf8)).privateRanges.isEmpty)
    }

    @Test func privateRangesTakePartInEquality() {
        let id = UUID().uuidString
        let date = Date()
        let marked = LogEntry(id: id, timestamp: date, level: .info, category: .user, subsystem: "t", message: "a b",
                              privateRanges: [0..<1])
        let unmarked = LogEntry(id: id, timestamp: date, level: .info, category: .user, subsystem: "t", message: "a b")
        #expect(marked != unmarked)
    }

    @Test func storesPrivateValuesFollowsTheBuildConfiguration() {
        #if DEBUG
        #expect(LogrConfiguration.default.storesPrivateValues)
        #else
        #expect(!LogrConfiguration.default.storesPrivateValues)
        #endif
        #expect(LogrConfiguration().storesPrivateValues == LogrConfiguration.default.storesPrivateValues)
    }

    @Test(arguments: [true, false])
    func storesPrivateValuesRoundTrips(value: Bool) throws {
        let configuration = LogrConfiguration(storesPrivateValues: value)
        let decoded = try JSONDecoder().decode(LogrConfiguration.self, from: JSONEncoder().encode(configuration))
        #expect(decoded.storesPrivateValues == value)
    }

    @Test func configurationsWithoutStoresPrivateValuesDecodeWithTheDefault() throws {
        let decoded = try JSONDecoder().decode(LogrConfiguration.self, from: Data(#"{"maxLogEntries":500}"#.utf8))
        #expect(decoded.storesPrivateValues == LogrConfiguration.default.storesPrivateValues)
    }
}

@Suite("Privacy hash key")
struct PrivacyHashKeyTests {
    private func bytes(_ key: SymmetricKey?) -> Data? {
        key?.withUnsafeBytes { Data($0) }
    }

    @Test func theKeyIsDerivedFromTheCurrentEncryptionKey() throws {
        let store = InMemoryKeychainStore()
        let service = LoggerCryptoService(store: store)
        let first = try #require(bytes(service.privacyHashKey()))

        #expect(try bytes(LoggerCryptoService(store: store).privacyHashKey()) == first)
        #expect(first.count == 32)
        #expect(!store.items.values.contains(first), "The encryption key itself must not be used for hashing")

        try service.rotateKey()
        #expect(try bytes(service.privacyHashKey()) != first)
    }

    @Test func theKeyCannotBeReadWhileTheKeychainIsLocked() {
        let service = LoggerCryptoService(store: LockableKeychainStore(isLocked: true))
        #expect(throws: LoggerCryptoError.keyTemporarilyUnavailable) { try service.privacyHashKey() }
    }

    @Test func customCryptoServicesHaveNoKeyByDefault() throws {
        struct Plain: LoggerCryptoServicing {
            func symmetricEncrypt(object: some Codable & Sendable) throws -> Data {
                try JSONEncoder().encode(object)
            }

            func symmetricDecrypt<T: Codable & Sendable>(encryptedData: Data) throws -> T {
                try JSONDecoder().decode(T.self, from: encryptedData)
            }
        }
        #expect(try Plain().privacyHashKey() == nil)
    }
}

@MainActor
@Suite("Private values through LogR", .timeLimit(.minutes(1)))
struct PrivateValuesLoggingTests {
    private let signals: AsyncStream<Void>
    private let signal: AsyncStream<Void>.Continuation

    init() {
        (signals, signal) = AsyncStream<Void>.makeStream()
    }

    private func makeLogger(storesPrivateValues: Bool,
                            storage: LogStorage = .memoryOnly,
                            keychain: any KeychainStore = InMemoryKeychainStore()) -> LogR {
        LogR(storage: storage, cryptoService: LoggerCryptoService(store: keychain),
             configuration: LogrConfiguration(mirrorToOSLog: false, storesPrivateValues: storesPrivateValues),
             analyser: nil, retrySignals: signals)
    }

    @Test func privateValuesAreStoredInClearAndMarkedWhenConfigured() throws {
        let logger = makeLogger(storesPrivateValues: true)
        let email = "zoë@example.com"

        logger.info("Signed in \(email) after \(3) tries")

        let entry = try #require(logger.recentLogs.first)
        #expect(entry.message == "Signed in zoë@example.com after 3 tries")
        #expect(entry.privateRanges == [10..<26])
    }

    @Test func privateValuesAreRedactedWhenNotStored() throws {
        let logger = makeLogger(storesPrivateValues: false)
        let email = "zoë@example.com"

        logger.info("Signed in \(email) after \(3) tries")

        let entry = try #require(logger.recentLogs.first)
        #expect(entry.message == "Signed in <private> after 3 tries")
        #expect(entry.privateRanges.isEmpty)
    }

    @Test(arguments: [true, false])
    func sensitiveValuesAreNeverStored(storesPrivateValues: Bool) throws {
        let logger = makeLogger(storesPrivateValues: storesPrivateValues)

        logger.info("token \("hunter2", privacy: .sensitive) for \("zoë")")

        let entry = try #require(logger.recentLogs.first)
        #expect(!entry.message.contains("hunter2"))
        #expect(entry.message.hasPrefix("token <sensitive> for "))
    }

    @Test func loggersWithoutStorageShareOneKeyAndNeverReadTheKeychain() {
        let keychain = InMemoryKeychainStore()
        let logger = makeLogger(storesPrivateValues: false, keychain: keychain)
        let other = makeLogger(storesPrivateValues: false, keychain: keychain)

        for user in ["u1", "u1", "u2"] {
            logger.info("user \(user, privacy: .private(mask: .hash))")
        }
        other.info("user \("u1", privacy: .private(mask: .hash))")

        let messages = logger.recentLogs.map(\.message)
        #expect(messages.allSatisfy { $0.wholeMatch(of: /user <private:[0-9a-f]{8}>/) != nil })
        #expect(messages[1] == messages[2])
        #expect(messages[0] != messages[1])
        #expect(other.recentLogs.first?.message == messages[1])
        #expect(keychain.items.isEmpty)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, *)
    @Test func hashedValuesArePrivateUntilTheKeyCanBeReadThenUseTheDerivedKey() async throws {
        let keychain = LockableKeychainStore(isLocked: true)
        let logger = makeLogger(storesPrivateValues: false, storage: .custom(FlakyStorage(failingFirst: 0)),
                                keychain: keychain)
        _ = await Observations { logger.persistenceStatus }.first { @Sendable in $0 == .waitingForProtectedData }

        logger.info("user \("u1", privacy: .private(mask: .hash))")
        #expect(logger.recentLogs.first?.message == "user <private>")

        keychain.unlock()
        signal.yield()
        _ = await Observations { logger.persistenceStatus }.first { @Sendable in $0 == .active }
        logger.info("user \("u1", privacy: .private(mask: .hash))")

        let key = try LoggerCryptoService(store: keychain.base).privacyHashKey()
        let expected = LogMessage("u1", privacy: .private(mask: .hash)).rendered(keepingPrivateValues: false,
                                                                                  hashKey: key)
        #expect(logger.recentLogs.first?.message == "user \(expected.text)")
        #expect(expected.text != "<private>")
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, *)
    @Test func hashingDoesNotWaitForStorageWhenTheKeyCanBeRead() async throws {
        let directory = try TemporaryDirectory()
        // A regular file where the storage's directory should be makes opening fail.
        let blocker = directory.url.appendingPathComponent("blocked")
        try Data().write(to: blocker)
        let keychain = InMemoryKeychainStore()
        let logger = makeLogger(storesPrivateValues: false, storage: .file(blocker.appendingPathComponent("l.ndjson")),
                                keychain: keychain)
        _ = await Observations { logger.persistenceStatus }.first { @Sendable status in
            if case .failed = status { true } else { false }
        }

        logger.info("user \("u1", privacy: .private(mask: .hash))")

        let key = try LoggerCryptoService(store: keychain).privacyHashKey()
        let expected = LogMessage("u1", privacy: .private(mask: .hash)).rendered(keepingPrivateValues: false,
                                                                                  hashKey: key)
        #expect(logger.recentLogs.first?.message == "user \(expected.text)")
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, *)
    @Test func privateRangesSurviveStorage() async throws {
        let keychain = InMemoryKeychainStore()
        let storage = FlakyStorage(failingFirst: 0)
        let logger = makeLogger(storesPrivateValues: true, storage: .custom(storage), keychain: keychain)

        logger.info("user \("zoë")")
        await logger.flush()

        let crypto = LoggerCryptoService(store: keychain)
        let stored: [LogEntry] = try await storage.entries.map { try crypto.symmetricDecrypt(encryptedData: $0.data) }
        #expect(stored.map(\.privateRanges) == [[5..<9]])
    }
}

@Suite("OSLog mirror")
struct OSLogMirrorTests {
    private let subsystem = "com.logr.tests.\(UUID().uuidString)"
    private let start = Date()

    private func makeLogger(verbosity: LogVerbosity, storesPrivateValues: Bool) -> LogR {
        LogR(cryptoService: LoggerCryptoService(store: InMemoryKeychainStore()),
             configuration: LogrConfiguration(subsystem: subsystem, logVerbosity: verbosity,
                                              storesPrivateValues: storesPrivateValues))
    }

    /// `format` pins which arguments are private. The text is checked against both forms: private arguments read in
    /// clear under a debugger (Xcode attaches LLDB to tests) or with private data logging on.
    private func expectMirrored(_ expected: [(format: String, redacted: String, clear: String)],
                                sourceLocation: SourceLocation = #_sourceLocation) throws {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let mirrored = try store.getEntries(at: store.position(date: start),
                                            matching: NSPredicate(format: "subsystem == %@", subsystem))
            .compactMap { $0 as? OSLogEntryLog }
        try #require(mirrored.count == expected.count, sourceLocation: sourceLocation)
        for (entry, forms) in zip(mirrored, expected) {
            #expect(entry.formatString == forms.format, sourceLocation: sourceLocation)
            let line = entry.composedMessage
            let matches = line == forms.redacted || line == forms.clear
            #expect(matches, "\(line)", sourceLocation: sourceLocation)
        }
    }

    /// The format of `count` private values in place.
    private func inPlace(_ count: Int) -> String {
        "%{public}s" + String(repeating: "%{private}s%{public}s", count: count)
    }

    @Test func privateValuesAreMirroredInPlace() throws {
        let logr = makeLogger(verbosity: .normal, storesPrivateValues: false)
        let (a, b, c, d, e) = ("A1", "B2", "C3", "D4", "E5")
        logr.info("Signed in \("zoe@example.com") after \(3) tries")
        logr.info("\(a) and \(b)")
        logr.info("x \(a)\(b)\(c)")
        logr.info("\(a)-\(b)-\(c)-\(d)!")
        logr.info("\(a) \(b) \(c) \(d) \(e)")
        logr.info("user \("zoe", privacy: .private(mask: .hash)) token \("hunter2", privacy: .sensitive) ok \(a)")
        logr.info("token \("hunter2", privacy: .sensitive)")
        let hashed = try #require(logr.recentLogs.dropFirst().first?.message)
        #expect(hashed.hasPrefix("user <private:"))

        try expectMirrored([
            (inPlace(1), "Signed in <private> after 3 tries", "Signed in zoe@example.com after 3 tries"),
            (inPlace(2), "<private> and <private>", "A1 and B2"),
            (inPlace(3), "x <private><private><private>", "x A1B2C3"),
            (inPlace(4), "<private>-<private>-<private>-<private>!", "A1-B2-C3-D4!"),
            // Five or more go after the text, joined.
            ("%{public}s %{private}s", String(repeating: "<private> ", count: 5) + "<private>",
             String(repeating: "<private> ", count: 5) + "A1, B2, C3, D4, E5"),
            (inPlace(1), hashed, hashed.replacingOccurrences(of: "ok <private>", with: "ok A1")),
            ("%{public}s", "token <sensitive>", "token <sensitive>")
        ])
    }

    @Test func verboseModeAppendsTheCallSite() throws {
        let logr = makeLogger(verbosity: .verbose, storesPrivateValues: true)
        logr.info("Signed in \("zoe") after \(3) tries", file: "App/Checkout.swift", function: "pay()", line: 42)
        logr.info("\("a") \("b") \("c") \("d") \("e")", file: "Checkout.swift", function: "pay()", line: 7)
        logr.info("user \("zoe", privacy: .private(mask: .hash))", file: "Checkout.swift", function: "pay()", line: 9)
        logr.info("\("zoe", privacy: .private(mask: .hash)) is \("zoe")", file: "Checkout.swift", function: "pay()",
                  line: 11)
        #expect(logr.recentLogs.first?.message == "zoe is zoe")

        // Loggers without storage share one hash key.
        let release = LogR(configuration: LogrConfiguration(mirrorToOSLog: false, storesPrivateValues: false))
        release.info("\("zoe", privacy: .private(mask: .hash))")
        let hash = try #require(release.recentLogs.first?.message)
        #expect(hash.hasPrefix("<private:"))
        try expectMirrored([
            (inPlace(1), "Signed in <private> after 3 tries (Checkout.swift:42 pay())",
             "Signed in zoe after 3 tries (Checkout.swift:42 pay())"),
            ("%{public}s %{private}s%{public}s",
             "<private> <private> <private> <private> <private> <private> (Checkout.swift:7 pay())",
             "<private> <private> <private> <private> <private> a, b, c, d, e (Checkout.swift:7 pay())"),
            ("%{public}s (%{public}s:%ld %{public}s)", "user \(hash) (Checkout.swift:9 pay())",
             "user \(hash) (Checkout.swift:9 pay())"),
            (inPlace(1), "\(hash) is <private> (Checkout.swift:11 pay())", "\(hash) is zoe (Checkout.swift:11 pay())")
        ])
    }
}
