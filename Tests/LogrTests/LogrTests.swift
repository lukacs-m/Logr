import Testing
@testable import Logr
import Foundation

@MainActor
@Suite("LogR Core Functionality")
struct LogrTests {
    @Test("Basic logging functionality")
    func basicLogging() async throws {
        let mockStorage = MockPersistentStorage()
        let config = LogrConfiguration(
            maxLogEntries: 100,
            maxLogAge: 24 * 60 * 60,
            enabledLevels: Set(LogLevel.allCases),
            subsystem: "com.logr.test",
            cleanupInterval: 5
        )
        let logr = LogR(storage: mockStorage, configuration: config)
        
        await logr.info("Test message")
        
        let entries = await mockStorage.getAllEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.message == "Test message")
        #expect(entries.first?.level == .info)
    }
    
    @Test("All log levels work correctly")
    func logLevels() async throws {
        let mockStorage = MockPersistentStorage()
        let config = LogrConfiguration(subsystem: "com.logr.test")
        let logr = LogR(storage: mockStorage, configuration: config)
        
        await logr.debug("Debug message")
        await logr.info("Info message")
        await logr.notice("Notice message")
        await logr.error("Error message")
        await logr.fault("Fault message")
        
        let entries = await mockStorage.getAllEntries()
        #expect(entries.count == 5)
        
        let levels = Set(entries.map(\.level))
        #expect(levels == Set(LogLevel.allCases))
    }
    
    @Test("Private data is properly redacted")
    func privateLogging() async throws {
        let mockStorage = MockPersistentStorage()
        let config = LogrConfiguration(subsystem: "com.logr.test")
        let logr = LogR(storage: mockStorage, configuration: config)
        
        let privateData = PrivateString("sensitive_info", privacy: .private)
        await logr.info("User data:", privateData: privateData)
        
        let entries = await mockStorage.getAllEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.message.contains("<private>") == true)
    }
    
    @Test("Log filtering works correctly")
    func logFiltering() async throws {
        let mockStorage = MockPersistentStorage()
        let config = LogrConfiguration(subsystem: "com.logr.test")
        let logr = LogR(storage: mockStorage, configuration: config)
        
        await logr.debug("Debug message", category: "test")
        await logr.info("Info message", category: "network")
        await logr.error("Error message", category: "test")
        
        let testEntries = try await logr.getLogs(categories: ["test"])
        #expect(testEntries.count == 2)
        
        let errorEntries = try await logr.getLogs(levels: [.error])
        #expect(errorEntries.count == 1)
    }
    
    @Test("Export formats work correctly")
    func exportFormats() async throws {
        let mockStorage = MockPersistentStorage()
        let config = LogrConfiguration(subsystem: "com.logr.test")
        let logr = LogR(storage: mockStorage, configuration: config)
        
        await logr.info("Test message")
        
        let jsonData = try await logr.exportLogs(format: .json)
        #expect(!jsonData.isEmpty)
        
        let csvData = try await logr.exportLogs(format: .csv)
        #expect(!csvData.isEmpty)
        let csvString = String(data: csvData, encoding: .utf8)
        #expect(csvString?.contains("Timestamp,Level,Category") == true)
        
        let txtData = try await logr.exportLogs(format: .txt)
        #expect(!txtData.isEmpty)
    }
    
    @Test("Clear logs functionality")
    func clearLogs() async throws {
        let mockStorage = MockPersistentStorage()
        let config = LogrConfiguration(subsystem: "com.logr.test")
        let logr = LogR(storage: mockStorage, configuration: config)
        
        await logr.info("Test message 1")
        await logr.info("Test message 2")
        
        var entries = await mockStorage.getAllEntries()
        #expect(entries.count == 2)
        
        try await logr.clearLogs()
        
        entries = await mockStorage.getAllEntries()
        #expect(entries.count == 0)
        #expect(logr.recentLogs.isEmpty)
    }
}

@Suite("LogEntry Tests")
struct LogEntryTests {
    @Test("LogEntry creation")
    func logEntryCreation() {
        let entry = LogEntry(
            level: .info,
            category: "test",
            subsystem: "com.test",
            message: "Test message"
        )
        
        #expect(entry.level == .info)
        #expect(entry.category == "test")
        #expect(entry.subsystem == "com.test")
        #expect(entry.message == "Test message")
    }
    
    @Test("LogEntry equality")
    func logEntryEquality() {
        let id = UUID()
        let timestamp = Date()
        let line = 140
        
        let entry1 = LogEntry(
            id: id,
            timestamp: timestamp,
            level: .info,
            category: "test",
            subsystem: "com.test",
            message: "Test message",
            line: line
        )
        
        let entry2 = LogEntry(
            id: id,
            timestamp: timestamp,
            level: .info,
            category: "test",
            subsystem: "com.test",
            message: "Test message",
            line: line
        )
        
        #expect(entry1 == entry2)
    }
}

@Suite("Configuration Tests")
struct LogrConfigurationTests {
    @Test("Default configuration values")
    func defaultConfiguration() {
        let config = LogrConfiguration.default
        
        #expect(config.maxLogEntries == 10_000)
        #expect(config.maxLogAge == 7 * 24 * 60 * 60)
        #expect(config.enabledLevels == Set(LogLevel.allCases))
        #expect(config.cleanupInterval == 60 * 60)
    }
    
    @Test("shouldLog filtering")
    func shouldLog() {
        let config = LogrConfiguration(
            enabledLevels: [.error, .fault]
        )
        
        #expect(!config.shouldLog(level: .debug))
        #expect(!config.shouldLog(level: .info))
        #expect(!config.shouldLog(level: .notice))
        #expect(config.shouldLog(level: .error))
        #expect(config.shouldLog(level: .fault))
    }
    
    @Test("JSON serialization")
    func jsonSerialization() throws {
        let config = LogrConfiguration(
            maxLogEntries: 1000,
            maxLogAge: 3600,
            enabledLevels: [.error, .fault],
            subsystem: "com.test"
        )
        
        let jsonString = try config.toJSONString()
        #expect(!jsonString.isEmpty)
        
        let decodedConfig = try LogrConfiguration.fromJSONString(jsonString)
        #expect(config.maxLogEntries == decodedConfig.maxLogEntries)
        #expect(config.maxLogAge == decodedConfig.maxLogAge)
        #expect(config.enabledLevels == decodedConfig.enabledLevels)
        #expect(config.subsystem == decodedConfig.subsystem)
    }
}

@Suite("Privacy Tests")
struct PrivateStringTests {
    @Test("Privacy redaction levels")
    func privateStringRedaction() {
        let publicString = PrivateString("public_data", privacy: .public)
        #expect(publicString.redacted == "public_data")
        
        let privateString = PrivateString("private_data", privacy: .private)
        #expect(privateString.redacted == "<private>")
        
        let sensitiveString = PrivateString("sensitive_data", privacy: .sensitive)
        #expect(sensitiveString.redacted == "<sensitive>")
    }
    
    @Test("String literal initialization")
    func stringLiteralInitialization() {
        let privateString: PrivateString = "test_data"
        #expect(privateString.value == "test_data")
        #expect(privateString.privacy == .private)
        #expect(privateString.redacted == "<private>")
    }
}

actor MockPersistentStorage: PersistentStorage {
    private var entries: [LogEntry] = []
    
    func store(_ entry: LogEntry) async throws {
        entries.append(entry)
        entries.sort { $0.timestamp > $1.timestamp }
    }
    
    func retrieve(
        levels: Set<LogLevel>?,
        categories: Set<String>?,
        subsystems: Set<String>?,
        from startDate: Date?,
        to endDate: Date?,
        limit: Int?
    ) async throws -> [LogEntry] {
        var filtered = entries
        
        if let levels = levels {
            filtered = filtered.filter { levels.contains($0.level) }
        }
        
        if let categories = categories {
            filtered = filtered.filter { categories.contains($0.category) }
        }
        
        if let subsystems = subsystems {
            filtered = filtered.filter { subsystems.contains($0.subsystem) }
        }
        
        if let startDate = startDate {
            filtered = filtered.filter { $0.timestamp >= startDate }
        }
        
        if let endDate = endDate {
            filtered = filtered.filter { $0.timestamp <= endDate }
        }
        
        filtered.sort { $0.timestamp > $1.timestamp }
        
        if let limit = limit {
            filtered = Array(filtered.prefix(limit))
        }
        
        return filtered
    }
    
    func deleteEntries(olderThan date: Date) async throws {
        entries = entries.filter { $0.timestamp >= date }
    }
    
    func deleteEntries(keepingLatest count: Int) async throws {
        entries.sort { $0.timestamp > $1.timestamp }
        entries = Array(entries.prefix(count))
    }
    
    func clear() async throws {
        entries.removeAll()
    }
    
    func count() async throws -> Int {
        return entries.count
    }
    
    func getAllEntries() async -> [LogEntry] {
        return entries
    }
}
