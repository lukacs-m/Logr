import Testing
@testable import Logr
import Foundation
import OSLog

@Suite("Models Tests")
struct ModelsTests {

    // MARK: - LogLevel Tests

    @Suite("LogLevel Tests")
    struct LogLevelTests {

        @Test("Test all log levels exist")
        func testAllLogLevelsExist() {
            let levels: [LogLevel] = [.debug, .info, .notice, .warning, .error, .fault]
            #expect(levels.count == 6)
        }

        @Test("Test log level raw values")
        func testLogLevelRawValues() {
            #expect(LogLevel.debug.rawValue == "debug")
            #expect(LogLevel.info.rawValue == "info")
            #expect(LogLevel.notice.rawValue == "notice")
            #expect(LogLevel.warning.rawValue == "warning")
            #expect(LogLevel.error.rawValue == "error")
            #expect(LogLevel.fault.rawValue == "fault")
        }

        @Test("Test log level display names")
        func testLogLevelDisplayNames() {
            #expect(LogLevel.debug.displayName == "Debug")
            #expect(LogLevel.info.displayName == "Info")
            #expect(LogLevel.notice.displayName == "Notice")
            #expect(LogLevel.warning.displayName == "Notice")
            #expect(LogLevel.error.displayName == "Error")
            #expect(LogLevel.fault.displayName == "Fault")
        }

        @Test("Test log level priorities")
        func testLogLevelPriorities() {
            #expect(LogLevel.debug.priority == 0)
            #expect(LogLevel.info.priority == 1)
            #expect(LogLevel.notice.priority == 2)
            #expect(LogLevel.warning.priority == 3)
            #expect(LogLevel.error.priority == 4)
            #expect(LogLevel.fault.priority == 5)

            // Verify priority order
            #expect(LogLevel.debug.priority < LogLevel.info.priority)
            #expect(LogLevel.info.priority < LogLevel.notice.priority)
            #expect(LogLevel.notice.priority < LogLevel.warning.priority)
            #expect(LogLevel.warning.priority < LogLevel.error.priority)
            #expect(LogLevel.error.priority < LogLevel.fault.priority)
        }

        @Test("Test log level OSLogType mapping")
        func testLogLevelOSLogTypeMapping() {
            #expect(LogLevel.debug.osLogType == .debug)
            #expect(LogLevel.info.osLogType == .info)
            #expect(LogLevel.notice.osLogType == .info)
            #expect(LogLevel.warning.osLogType == .default)
            #expect(LogLevel.error.osLogType == .error)
            #expect(LogLevel.fault.osLogType == .fault)
        }

        @Test("Test log level codable")
        func testLogLevelCodable() throws {
            let level = LogLevel.error
            let encoder = JSONEncoder()
            let data = try encoder.encode(level)

            let decoder = JSONDecoder()
            let decodedLevel = try decoder.decode(LogLevel.self, from: data)

            #expect(decodedLevel == level)
        }

        @Test("Test all log levels are codable")
        func testAllLogLevelsAreCodable() throws {
            let levels: [LogLevel] = [.debug, .info, .notice, .warning, .error, .fault]

            for level in levels {
                let encoder = JSONEncoder()
                let data = try encoder.encode(level)

                let decoder = JSONDecoder()
                let decodedLevel = try decoder.decode(LogLevel.self, from: data)

                #expect(decodedLevel == level)
            }
        }

        @Test("Test log level visual queue")
        func testLogLevelVisualQueue() {
            #expect(LogLevel.debug.visualQueue == "🟣")
            #expect(LogLevel.info.visualQueue == "🔵")
            #expect(LogLevel.notice.visualQueue == "🔵")
            #expect(LogLevel.warning.visualQueue == "🟡")
            #expect(LogLevel.error.visualQueue == "🔴")
            #expect(LogLevel.fault.visualQueue == "🔴")
        }

        @Test("Test log level CaseIterable")
        func testLogLevelCaseIterable() {
            let allCases = LogLevel.allCases
            #expect(allCases.count == 6)
            #expect(allCases.contains(.debug))
            #expect(allCases.contains(.info))
            #expect(allCases.contains(.notice))
            #expect(allCases.contains(.warning))
            #expect(allCases.contains(.error))
            #expect(allCases.contains(.fault))
        }
    }

    // MARK: - LogCategory Tests

    @Suite("LogCategory Tests")
    struct LogCategoryTests {

        @Test("Test predefined categories")
        func testPredefinedCategories() {
            let categories: [LogCategory] = [
                .system, .network, .ui, .database, .authentication,
                .performance, .debug, .test, .mock
            ]

            for category in categories {
                #expect(!category.rawValue.isEmpty)
                #expect(!category.displayName.isEmpty)
            }
        }

        @Test("Test custom category")
        func testCustomCategory() {
            let custom = LogCategory.custom("MyCustomCategory")
            #expect(custom.rawValue == "MyCustomCategory")
            #expect(custom.displayName == "Mycustomcategory")
        }

        @Test("Test category raw values")
        func testCategoryRawValues() {
            #expect(LogCategory.system.rawValue == "system")
            #expect(LogCategory.network.rawValue == "network")
            #expect(LogCategory.ui.rawValue == "ui")
            #expect(LogCategory.database.rawValue == "database")
        }

        @Test("Test category display names")
        func testCategoryDisplayNames() {
            #expect(LogCategory.system.displayName == "System")
            #expect(LogCategory.network.displayName == "Network")
            #expect(LogCategory.ui.displayName == "User Interface")
            #expect(LogCategory.database.displayName == "Database")
        }

        @Test("Test common categories")
        func testCommonCategories() {
            let common = LogCategory.common
            #expect(common.count == 7)
            #expect(common.contains(.system))
            #expect(common.contains(.network))
            #expect(common.contains(.ui))
            #expect(common.contains(.authentication))
            #expect(common.contains(.database))
            #expect(common.contains(.performance))
            #expect(common.contains(.debug))
        }

        @Test("Test predefined categories list")
        func testPredefinedCategoriesList() {
            let predefined = LogCategory.predefined
            #expect(predefined.count > 0)
            #expect(predefined.contains(.system))
            #expect(predefined.contains(.network))
        }

        @Test("Test category initialization from raw value")
        func testCategoryInitializationFromRawValue() {
            let systemCategory = LogCategory(rawValue: "system")
            #expect(systemCategory == .system)

            let customCategory = LogCategory(rawValue: "nonexistent")
            #expect(customCategory == .custom("nonexistent"))
        }

        @Test("Test category codable")
        func testCategoryCodable() throws {
            let category = LogCategory.network
            let encoder = JSONEncoder()
            let data = try encoder.encode(category)

            let decoder = JSONDecoder()
            let decodedCategory = try decoder.decode(LogCategory.self, from: data)

            #expect(decodedCategory == category)
        }

        @Test("Test custom category codable")
        func testCustomCategoryCodable() throws {
            let category = LogCategory.custom("MyCategory")
            let encoder = JSONEncoder()
            let data = try encoder.encode(category)

            let decoder = JSONDecoder()
            let decodedCategory = try decoder.decode(LogCategory.self, from: data)

            #expect(decodedCategory == category)
        }

        @Test("Test category hashable")
        func testCategoryHashable() {
            var categorySet: Set<LogCategory> = []
            categorySet.insert(.system)
            categorySet.insert(.network)
            categorySet.insert(.system) // duplicate

            #expect(categorySet.count == 2)
            #expect(categorySet.contains(.system))
            #expect(categorySet.contains(.network))
        }

        @Test("Test category identifiable")
        func testCategoryIdentifiable() {
            let category = LogCategory.system
            #expect(category.id == category.rawValue)
        }

        @Test("Test category description")
        func testCategoryDescription() {
            let category = LogCategory.network
            #expect(category.description == category.displayName)
        }

        @Test("Test all predefined categories are codable")
        func testAllPredefinedCategoriesAreCodable() throws {
            let categories = LogCategory.predefined

            for category in categories {
                let encoder = JSONEncoder()
                let data = try encoder.encode(category)

                let decoder = JSONDecoder()
                let decodedCategory = try decoder.decode(LogCategory.self, from: data)

                #expect(decodedCategory == category)
            }
        }
    }

    // MARK: - LogEntry Tests

    @Suite("LogEntry Tests")
    struct LogEntryTests {

        @Test("Test log entry initialization")
        func testLogEntryInitialization() {
            let entry = LogEntry(
                level: .info,
                category: .system,
                subsystem: "com.test",
                message: "Test message"
            )

            #expect(!entry.id.isEmpty)
            #expect(entry.level == .info)
            #expect(entry.category == .system)
            #expect(entry.subsystem == "com.test")
            #expect(entry.message == "Test message")
            #expect(entry.timestamp <= Date())
        }

        @Test("Test log entry with custom timestamp")
        func testLogEntryWithCustomTimestamp() {
            let customTimestamp = Date(timeIntervalSince1970: 1000000)
            let entry = LogEntry(
                timestamp: customTimestamp,
                level: .error,
                category: .network,
                subsystem: "com.test",
                message: "Error occurred"
            )

            #expect(entry.timestamp == customTimestamp)
        }

        @Test("Test log entry with custom ID")
        func testLogEntryWithCustomID() {
            let customID = "custom-log-id"
            let entry = LogEntry(
                id: customID,
                level: .debug,
                category: .debug,
                subsystem: "com.test",
                message: "Debug info"
            )

            #expect(entry.id == customID)
        }

        @Test("Test log entry codable")
        func testLogEntryCodable() throws {
            let entry = LogEntry(
                level: .warning,
                category: .security,
                subsystem: "com.test.security",
                message: "Security warning"
            )

            let encoder = JSONEncoder()
            let data = try encoder.encode(entry)

            let decoder = JSONDecoder()
            let decodedEntry = try decoder.decode(LogEntry.self, from: data)

            #expect(decodedEntry.id == entry.id)
            #expect(decodedEntry.level == entry.level)
            #expect(decodedEntry.category == entry.category)
            #expect(decodedEntry.subsystem == entry.subsystem)
            #expect(decodedEntry.message == entry.message)
        }

        @Test("Test log entry with file, function, line")
        func testLogEntryWithFileAndFunction() {
            let entry = LogEntry(
                level: .error,
                category: .system,
                subsystem: "com.test",
                message: "Error",
                file: "/path/to/file.swift",
                function: "testFunction()",
                line: 42
            )

            #expect(entry.file == "/path/to/file.swift")
            #expect(entry.function == "testFunction()")
            #expect(entry.line == 42)
        }

        @Test("Test log entry identifiable")
        func testLogEntryIdentifiable() {
            let entry = LogEntry(
                level: .info,
                category: .system,
                subsystem: "com.test",
                message: "Test"
            )

            #expect(entry.id == entry.id) // ID should be consistent
        }

        @Test("Test log entry hashable")
        func testLogEntryHashable() {
            let date = Date.now
            let entry1 = LogEntry(
                id: "same-id",
                timestamp: date,
                level: .info,
                category: .system,
                subsystem: "com.test",
                message: "Test 1"
            )

            let entry2 = LogEntry(
                id: "same-id",
                timestamp: date,
                level: .info,
                category: .system,
                subsystem: "com.test",
                message: "Test 1"
            )

            var entrySet: Set<LogEntry> = []
            entrySet.insert(entry1)
            entrySet.insert(entry2)

            #expect(entrySet.count == 1) // Same ID should be treated as same entry
        }

        @Test("Test log entry with empty message")
        func testLogEntryWithEmptyMessage() {
            let entry = LogEntry(
                level: .info,
                category: .system,
                subsystem: "com.test",
                message: ""
            )

            #expect(entry.message == "")
        }

        @Test("Test log entry with long message")
        func testLogEntryWithLongMessage() {
            let longMessage = String(repeating: "A", count: 10000)
            let entry = LogEntry(
                level: .info,
                category: .system,
                subsystem: "com.test",
                message: longMessage
            )

            #expect(entry.message.count == 10000)
        }

        @Test("Test log entry with unicode message")
        func testLogEntryWithUnicodeMessage() {
            let unicodeMessage = "Hello 世界 🌍 مرحبا"
            let entry = LogEntry(
                level: .info,
                category: .system,
                subsystem: "com.test",
                message: unicodeMessage
            )

            #expect(entry.message == unicodeMessage)
        }

        @Test("Test log entry with special characters")
        func testLogEntryWithSpecialCharacters() {
            let specialMessage = "Special: \n\t\"quotes\" and \\backslash\\"
            let entry = LogEntry(
                level: .info,
                category: .system,
                subsystem: "com.test",
                message: specialMessage
            )

            #expect(entry.message == specialMessage)
        }
    }

    // MARK: - EncryptedLogEntry Tests

    @Suite("EncryptedLogEntry Tests")
    struct EncryptedLogEntryTests {

        @Test("Test encrypted log entry initialization")
        func testEncryptedLogEntryInitialization() {
            let data = Data("encrypted".utf8)
            let timestamp = Date()
            let entry = EncryptedLogEntry(
                id: "test-id",
                timestamp: timestamp,
                data: data
            )

            #expect(entry.id == "test-id")
            #expect(entry.timestamp == timestamp)
            #expect(entry.data == data)
        }

        @Test("Test encrypted log entry codable")
        func testEncryptedLogEntryCodable() throws {
            let data = Data("encrypted data".utf8)
            let entry = EncryptedLogEntry(
                id: "test-id",
                timestamp: Date(),
                data: data
            )

            let encoder = JSONEncoder()
            let encodedData = try encoder.encode(entry)

            let decoder = JSONDecoder()
            let decodedEntry = try decoder.decode(EncryptedLogEntry.self, from: encodedData)

            #expect(decodedEntry.id == entry.id)
            #expect(decodedEntry.data == entry.data)
        }

        @Test("Test encrypted log entry with empty data")
        func testEncryptedLogEntryWithEmptyData() {
            let entry = EncryptedLogEntry(
                id: "test-id",
                timestamp: Date(),
                data: Data()
            )

            #expect(entry.data.isEmpty)
        }

        @Test("Test encrypted log entry with large data")
        func testEncryptedLogEntryWithLargeData() {
            let largeData = Data(repeating: 0xFF, count: 100000)
            let entry = EncryptedLogEntry(
                id: "test-id",
                timestamp: Date(),
                data: largeData
            )

            #expect(entry.data.count == 100000)
        }

        @Test("Test encrypted log entry identifiable")
        func testEncryptedLogEntryIdentifiable() {
            let entry = EncryptedLogEntry(
                id: "unique-id",
                timestamp: Date(),
                data: Data()
            )

            #expect(entry.id == "unique-id")
        }

        @Test("Test encrypted log entry hashable")
        func testEncryptedLogEntryHashable() {
            let date = Date.now

            let entry1 = EncryptedLogEntry(
                id: "same-id",
                timestamp: date,
                data: Data("data".utf8)
            )

            let entry2 = EncryptedLogEntry(
                id: "same-id",
                timestamp: date,
                data: Data("data".utf8)
            )

            var entrySet: Set<EncryptedLogEntry> = []
            entrySet.insert(entry1)
            entrySet.insert(entry2)

            #expect(entrySet.count == 1)
        }
    }

    // MARK: - LogrConfiguration Tests

    @Suite("LogrConfiguration Tests")
    struct LogrConfigurationTests {

        @Test("Test default configuration")
        func testDefaultConfiguration() {
            let config = LogrConfiguration.default

            #expect(config.maxLogEntries == 10_000)
            #expect(config.maxLogAge == 7 * 24 * 60 * 60) // 7 days
            #expect(config.enabledLevels == Set(LogLevel.allCases))
            #expect(config.cleanupInterval == 60 * 60) // 1 hour
            #expect(config.logVerbosity == .verbose)
        }

        @Test("Test custom configuration")
        func testCustomConfiguration() {
            let config = LogrConfiguration(
                maxLogEntries: 100,
                maxLogAge: 86400, // 1 day
                enabledLevels: [.error, .fault],
                subsystem: "com.custom.app",
                cleanupInterval: 300, // 5 minutes
                logVerbosity: .normal
            )

            #expect(config.maxLogEntries == 100)
            #expect(config.maxLogAge == 86400)
            #expect(config.enabledLevels == [.error, .fault])
            #expect(config.subsystem == "com.custom.app")
            #expect(config.cleanupInterval == 300)
            #expect(config.logVerbosity == .normal)
        }

        @Test("Test configuration codable")
        func testConfigurationCodable() throws {
            let config = LogrConfiguration(
                maxLogEntries: 500,
                maxLogAge: 3600,
                enabledLevels: [.debug, .info],
                subsystem: "com.test",
                cleanupInterval: 600,
                logVerbosity: .verbose
            )

            let encoder = JSONEncoder()
            let data = try encoder.encode(config)

            let decoder = JSONDecoder()
            let decodedConfig = try decoder.decode(LogrConfiguration.self, from: data)

            #expect(decodedConfig.maxLogEntries == config.maxLogEntries)
            #expect(decodedConfig.maxLogAge == config.maxLogAge)
            #expect(decodedConfig.enabledLevels == config.enabledLevels)
            #expect(decodedConfig.subsystem == config.subsystem)
            #expect(decodedConfig.cleanupInterval == config.cleanupInterval)
            #expect(decodedConfig.logVerbosity == config.logVerbosity)
        }

        @Test("Test log verbosity values")
        func testLogVerbosityValues() {
            #expect(LogVerbosity.verbose == .verbose)
            #expect(LogVerbosity.normal == .normal)
            #expect(LogVerbosity.verbose != .normal)
        }

        @Test("Test configuration with partial parameters")
        func testConfigurationWithPartialParameters() {
            let config = LogrConfiguration(maxLogEntries: 50)

            #expect(config.maxLogEntries == 50)
            // Other values should be defaults
            #expect(config.maxLogAge == LogrConfiguration.default.maxLogAge)
            #expect(config.enabledLevels == LogrConfiguration.default.enabledLevels)
        }
    }
}
