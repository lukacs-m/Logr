import Foundation
import Testing
@testable import Logr
import LogrTesting

/// What the files in `Fixtures/` hold. They were written once by Logr 1.3 and must never be
/// regenerated: they pin the 1.x on-disk formats that later releases have to keep reading.
enum LegacyFixtures {
    static let entries: [LogEntry] = (0 ..< 20).map { index in
        LogEntry(id: String(format: "00000000-0000-0000-0000-%012d", index),
                 // Whole seconds: FileSystemStorage writes ISO 8601 dates, which drop fractions.
                 timestamp: Date(timeIntervalSince1970: 1_767_225_600 + Double(index) * 60),
                 level: LogLevel.allCases[index % LogLevel.allCases.count],
                 category: categories[index % categories.count],
                 subsystem: "com.logr.fixtures",
                 message: "Fixture entry \(index)",
                 file: "/App/Sources/Checkout/CheckoutView.swift",
                 function: "submit(order:)",
                 line: 100 + index,
                 metadata: metadata[index % metadata.count])
    }

    static let configuration = LogrConfiguration(maxLogEntries: 2_000,
                                                 maxLogAge: 3 * 24 * 60 * 60,
                                                 enabledLevels: [.info, .warning, .error, .fault],
                                                 categoryLevelOverrides: [.network: .warning,
                                                                          .custom("Checkout"): .debug],
                                                 subsystem: "com.logr.fixtures",
                                                 cleanupInterval: 600,
                                                 logVerbosity: .normal,
                                                 coalesceWindowMillis: 250,
                                                 mirrorToOSLog: false)

    private static let categories: [LogCategory] = [.system, .network, .custom("Checkout"), .database,
                                                    .custom("Feature Flags"), .ui, .authentication]

    private static let metadata: [[String: LogMetadataValue]?] = [
        nil,
        ["status": .int(200), "duration": .double(0.25)],
        ["user": .string("u-42"), "premium": .bool(true)],
        ["at": .date(Date(timeIntervalSince1970: 1_767_225_600))],
        ["tags": .array([.string("a"), .int(1)]), "nested": .dictionary(["key": .string("value")])]
    ]

    static func url(_ name: String) throws -> URL {
        try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appendingPathComponent(name)
    }

    /// The Keychain items the fixtures were encrypted with: the key bytes and the version record.
    static func keychain() throws -> InMemoryKeychainStore {
        try InMemoryKeychainStore(items: JSONDecoder().decode([String: Data].self,
                                                              from: Data(contentsOf: url("keychain.json"))))
    }
}

@Suite("Legacy 1.x fixtures")
struct LegacyFixtureTests {
    private let directory: TemporaryDirectory

    init() throws {
        directory = try TemporaryDirectory()
    }

    @Test func keychainFixtureIsAdoptedWithoutNewKeys() throws {
        let store = try LegacyFixtures.keychain()
        let items = store.items

        let crypto = try LoggerCryptoService(store: store)

        #expect(crypto.currentKeyVersion.value == KeyVersion(1))
        #expect(store.items == items)
    }

    @Test func sqliteFixtureDecrypts() async throws {
        let storage = try SQLiteStorage(databasePath: copyFixture("legacy.sqlite").path)

        #expect(try await decrypt(storage.fetchEntries()) == LegacyFixtures.entries)
    }

    @Test(arguments: ["legacy-ndjson.json", "legacy-array-newest-first.json"])
    func fileFixtureDecryptsOldestFirst(fileName: String) async throws {
        _ = try copyFixture(fileName)
        let storage = try FileSystemStorage(directory: directory.url, fileName: fileName)

        #expect(try await decrypt(storage.fetchEntries()) == LegacyFixtures.entries)
        #expect(try await storage.fetchEntries(limit: 5).map(\.id) == LegacyFixtures.entries.suffix(5).map(\.id))
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, *)
    @Test(.timeLimit(.minutes(1)))
    func arrayFixtureLoadsNewestFirstIntoRecentLogs() async throws {
        _ = try copyFixture("legacy-array-newest-first.json")
        let storage = try FileSystemStorage(directory: directory.url, fileName: "legacy-array-newest-first.json")
        let logger = try LogR(storage: storage, cryptoService: LoggerCryptoService(store: LegacyFixtures.keychain()),
                              configuration: LogrConfiguration(mirrorToOSLog: false))

        let loaded = await Observations { logger.recentLogs }.first { $0.count == LegacyFixtures.entries.count }

        #expect(loaded?.map(\.id) == LegacyFixtures.entries.reversed().map(\.id))
    }

    @Test func chachaEnvelopeWithoutAlgorithmDecrypts() throws {
        let envelope = try Data(contentsOf: LegacyFixtures.url("legacy-envelope-chacha-no-algorithm.json"))
        #expect(!String(decoding: envelope, as: UTF8.self).contains("algorithm"))

        let entry: LogEntry = try LoggerCryptoService(store: LegacyFixtures.keychain())
            .symmetricDecrypt(encryptedData: envelope)

        #expect(entry == LegacyFixtures.entries[0])
    }

    @Test func configurationFixtureDecodes() throws {
        let data = try Data(contentsOf: LegacyFixtures.url("legacy-configuration.json"))
        let expected = LegacyFixtures.configuration

        let decoded = try JSONDecoder().decode(LogrConfiguration.self, from: data)

        #expect(decoded.maxLogEntries == expected.maxLogEntries)
        #expect(decoded.maxLogAge == expected.maxLogAge)
        #expect(decoded.enabledLevels == expected.enabledLevels)
        #expect(decoded.categoryLevelOverrides == expected.categoryLevelOverrides)
        #expect(decoded.subsystem == expected.subsystem)
        #expect(decoded.cleanupInterval == expected.cleanupInterval)
        #expect(decoded.logVerbosity == expected.logVerbosity)
        #expect(decoded.coalesceWindowMillis == expected.coalesceWindowMillis)
        #expect(decoded.mirrorToOSLog == expected.mirrorToOSLog)
    }

    /// Storages rewrite what they open (migration, retention), so tests work on a copy.
    private func copyFixture(_ name: String) throws -> URL {
        let copy = directory.url.appendingPathComponent(name)
        try FileManager.default.copyItem(at: LegacyFixtures.url(name), to: copy)
        return copy
    }

    private func decrypt(_ entries: [EncryptedLogEntry]) throws -> [LogEntry] {
        let crypto = try LoggerCryptoService(store: LegacyFixtures.keychain())
        let decrypted: [LogEntry] = try entries.map { try crypto.symmetricDecrypt(encryptedData: $0.data) }
        #expect(decrypted.map(\.id) == entries.map(\.id))
        return decrypted
    }
}
