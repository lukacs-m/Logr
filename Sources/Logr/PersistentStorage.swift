import Foundation

public protocol PersistentStorage: Sendable {
    func store(_ entry: LogEntry) async throws
    func retrieve(
        levels: Set<LogLevel>?,
        categories: Set<String>?,
        subsystems: Set<String>?,
        from startDate: Date?,
        to endDate: Date?,
        limit: Int?
    ) async throws -> [LogEntry]
    func deleteEntries(olderThan date: Date) async throws
    func deleteEntries(keepingLatest count: Int) async throws
    func clear() async throws
    func count() async throws -> Int
}

public actor FileSystemStorage: PersistentStorage {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    public init(fileName: String = "logr_entries.json") throws {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = documentsPath.appendingPathComponent(fileName)
        
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        
        try createFileIfNeededSync()
    }
    
    nonisolated private func createFileIfNeededSync() throws {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let emptyEntries: [LogEntry] = []
            let data = try encoder.encode(emptyEntries)
            try data.write(to: fileURL)
        }
    }
    
    private func loadEntries() throws -> [LogEntry] {
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([LogEntry].self, from: data)
    }
    
    private func saveEntries(_ entries: [LogEntry]) throws {
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }
    
    public func store(_ entry: LogEntry) async throws {
        var entries = try loadEntries()
        entries.append(entry)
        
        entries.sort { $0.timestamp > $1.timestamp }
        try saveEntries(entries)
    }
    
    public func retrieve(
        levels: Set<LogLevel>? = nil,
        categories: Set<String>? = nil,
        subsystems: Set<String>? = nil,
        from startDate: Date? = nil,
        to endDate: Date? = nil,
        limit: Int? = nil
    ) async throws -> [LogEntry] {
        let entries = try loadEntries()
        
        var filteredEntries = entries
        
        if let levels = levels {
            filteredEntries = filteredEntries.filter { levels.contains($0.level) }
        }
        
        if let categories = categories {
            filteredEntries = filteredEntries.filter { categories.contains($0.category) }
        }
        
        if let subsystems = subsystems {
            filteredEntries = filteredEntries.filter { subsystems.contains($0.subsystem) }
        }
        
        if let startDate = startDate {
            filteredEntries = filteredEntries.filter { $0.timestamp >= startDate }
        }
        
        if let endDate = endDate {
            filteredEntries = filteredEntries.filter { $0.timestamp <= endDate }
        }
        
        filteredEntries.sort { $0.timestamp > $1.timestamp }
        
        if let limit = limit {
            filteredEntries = Array(filteredEntries.prefix(limit))
        }
        
        return filteredEntries
    }
    
    public func deleteEntries(olderThan date: Date) async throws {
        let entries = try loadEntries()
        let filteredEntries = entries.filter { $0.timestamp >= date }
        try saveEntries(filteredEntries)
    }
    
    public func deleteEntries(keepingLatest count: Int) async throws {
        let entries = try loadEntries()
        let sortedEntries = entries.sorted { $0.timestamp > $1.timestamp }
        let entriesToKeep = Array(sortedEntries.prefix(count))
        try saveEntries(entriesToKeep)
    }
    
    public func clear() async throws {
        try saveEntries([])
    }
    
    public func count() async throws -> Int {
        return try loadEntries().count
    }
}