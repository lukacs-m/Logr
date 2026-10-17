//
//  LogStorage.swift
//  Logr
//

import Foundation

/// Where ``LogR`` persists entries.
///
/// ``LogR`` opens the storage on its background writer, not in its initializer, so creating a logger never
/// throws. While the storage cannot be opened or the encryption key cannot be read, for example before the
/// device's first unlock after a restart, entries wait in memory and opening is retried;
/// ``LogRService/persistenceStatus`` reports why.
public enum LogStorage: Sendable {
    /// No persistence: entries live in memory only.
    case memoryOnly

    /// An SQLite database (``SQLiteStorage``) at the given file URL, or at
    /// `Application Support/<bundle id>/logs.sqlite` when `nil`.
    case sqlite(URL? = nil)

    /// An append-only file of one JSON entry per line (``FileSystemStorage``) at the given file URL, or at
    /// `Application Support/<bundle id>/Logr/logr_entries.ndjson` when `nil`.
    case file(URL? = nil)

    /// A storage you created yourself, such as your own ``LogRPersistence`` conformance.
    case custom(any LogRPersistence)
}

extension LogStorage {
    /// Opens the storage; `nil` for ``memoryOnly``.
    func open() throws -> (any LogRPersistence)? {
        switch self {
        case .memoryOnly:
            return nil
        case let .sqlite(url):
            guard let url else { return try SQLiteStorage() }
            return try SQLiteStorage(databasePath: url.path)
        case let .file(url):
            guard let url else { return try FileSystemStorage() }
            return try FileSystemStorage(directory: url.deletingLastPathComponent(),
                                         fileName: url.lastPathComponent)
        case let .custom(storage):
            return storage
        }
    }
}
