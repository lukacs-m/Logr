//
//  LogRPersistence.swift
//  Logr
//
//  Created by martin on 02/11/2025.
//

import Foundation

/// Protocol for persistent storage of encrypted log entries.
///
/// `LogRPersistence` defines the interface for storing, retrieving, and managing
/// encrypted log entries. All log data is encrypted before storage using the crypto service.
///
/// ## Overview
///
/// LogR provides two built-in implementations:
/// - ``FileSystemStorage``: Simple JSON-based file storage
/// - ``SQLiteStorage``: High-performance SQLite database storage
///
/// You can also implement custom storage backends (cloud storage, Core Data, etc.)
/// by conforming to this protocol.
///
/// ## Thread Safety
///
/// All operations are `async` and implementations must be thread-safe (`Sendable`).
/// The logging system calls these methods from a background actor to avoid blocking
/// the main thread.
///
/// ## Example Implementation
///
/// ```swift
/// import Logr
///
/// class CloudStorage: LogRPersistence {
///     func store(_ entry: EncryptedLogEntry) async throws {
///         // Upload to cloud service
///         try await uploadToCloud(entry)
///     }
///
///     func fetchEntries() async throws -> [EncryptedLogEntry] {
///         // Fetch from cloud service
///         return try await fetchFromCloud()
///     }
///
///     // Implement other required methods...
/// }
///
/// let logger = LogR(storage: CloudStorage())
/// ```
///
/// ## Topics
///
/// ### Storage Operations
/// - ``store(_:)``
/// - ``fetchEntries()``
///
/// ### Cleanup Operations
/// - ``deleteEntries(olderThan:)``
/// - ``deleteEntries(keepingLatest:)``
/// - ``clear()``
///
/// ### Query Operations
/// - ``count()``
public protocol LogRPersistence: Sendable {
    /// Stores an encrypted log entry.
    ///
    /// This method is called by the background writer actor for each log entry.
    /// Implementations should handle storage errors gracefully and be performant.
    ///
    /// - Parameter entry: The encrypted log entry to store.
    /// - Throws: Storage-specific errors if the operation fails.
    ///
    /// ## Implementation Notes
    ///
    /// - Should be atomic (all or nothing)
    /// - Should be performant (called frequently)
    /// - Should handle concurrent calls safely
    func store(_ entry: EncryptedLogEntry) async throws

    /// Stores batch of encrypted log entries.
    ///
    /// This method is called by the background writer actor for eachbatch of logs.
    /// Implementations should handle storage errors gracefully and be performant.
    ///
    /// - Parameter entries: A batch of encrypted log entry to store.
    /// - Throws: Storage-specific errors if the operation fails.
    ///
    /// ## Implementation Notes
    ///
    /// - Should be atomic (all or nothing)
    /// - Should be performant (called frequently)
    /// - Should handle concurrent calls safely
    func store(_ entries: [EncryptedLogEntry]) async throws

    /// Fetches all stored encrypted log entries.
    ///
    /// Returns entries in chronological order (oldest first). The entries
    /// will be decrypted by the crypto service after retrieval.
    ///
    /// - Returns: Array of encrypted log entries.
    /// - Throws: Storage-specific errors if the operation fails.
    ///
    /// ## Performance Considerations
    ///
    /// This method is called during logger initialization. For large log sets,
    /// consider implementing pagination or limiting the returned entries.
    func fetchEntries() async throws -> [EncryptedLogEntry]

    /// Fetches the most recent stored entries (up to `limit`), oldest first.
    ///
    /// Passing `nil` returns all entries (equivalent to ``fetchEntries()``). This is used
    /// at logger startup to load only as many entries as the in-memory cache holds, rather
    /// than decrypting the entire persisted history.
    ///
    /// A default implementation fetches everything and returns the latest `limit`.
    /// Conformers backed by a query engine should override this to push the limit down to
    /// storage (e.g. `ORDER BY timestamp DESC LIMIT ?`).
    ///
    /// - Parameter limit: The maximum number of (most recent) entries to return, or `nil`
    ///   for all entries.
    func fetchEntries(limit: Int?) async throws -> [EncryptedLogEntry]

    /// Deletes log entries older than the specified date.
    ///
    /// Part of the automatic cleanup process. Called periodically based on
    /// the configured cleanup interval and `maxLogAge`.
    ///
    /// - Parameter date: The cutoff date. Entries older than this are deleted.
    /// - Throws: Storage-specific errors if the operation fails.
    func deleteEntries(olderThan date: Date) async throws

    /// Deletes old entries, keeping only the most recent ones.
    ///
    /// Part of the automatic cleanup process. Called when the total entry count
    /// exceeds `maxLogEntries` in the configuration.
    ///
    /// - Parameter count: The number of most recent entries to keep.
    /// - Throws: Storage-specific errors if the operation fails.
    ///
    /// ## Example
    /// If there are 15,000 entries and `count` is 10,000, this should delete
    /// the oldest 5,000 entries.
    func deleteEntries(keepingLatest count: Int) async throws

    /// Clears all stored log entries.
    ///
    /// Called when the user explicitly clears logs via `clearLogs()`.
    /// Should remove all entries from storage completely.
    ///
    /// - Throws: Storage-specific errors if the operation fails.
    func clear() async throws

    /// Returns the total number of stored log entries.
    ///
    /// Used by the cleanup system to determine if pruning is needed.
    ///
    /// - Returns: The count of stored entries.
    /// - Throws: Storage-specific errors if the operation fails.
    func count() async throws -> Int
}

public extension LogRPersistence {
    /// Default implementation: stores each entry via the single-entry primitive.
    ///
    /// Keeps ``store(_:)-batch`` an additive, non-breaking requirement for existing conformers —
    /// a custom backend that only implements the single-entry `store(_:)` still compiles.
    /// Built-in backends (``SQLiteStorage``, ``FileSystemStorage``) override this with a single
    /// batched write, which is far more efficient and should be preferred whenever the backend
    /// supports it.
    func store(_ entries: [EncryptedLogEntry]) async throws {
        for entry in entries {
            try await store(entry)
        }
    }

    /// Default implementation: fetches all entries and returns the latest `limit`,
    /// preserving the oldest-first order. Override for storage that can apply the limit
    /// natively.
    func fetchEntries(limit: Int?) async throws -> [EncryptedLogEntry] {
        let all = try await fetchEntries()
        guard let limit, limit < all.count else { return all }
        return Array(all.suffix(limit))
    }
}
