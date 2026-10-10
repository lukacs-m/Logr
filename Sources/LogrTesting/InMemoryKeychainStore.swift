//
//  InMemoryKeychainStore.swift
//  LogrTesting
//

import Foundation
import Logr
import os

/// A `KeychainStore` that keeps its items in memory, so a `LoggerCryptoService` can run in tests
/// without touching the Keychain.
///
/// Each instance starts with the items it was given and forgets them when released. All methods
/// are thread-safe.
///
/// ```swift
/// let crypto = try LoggerCryptoService(store: InMemoryKeychainStore())
/// let logr = LogR(cryptoService: crypto)
/// ```
public final class InMemoryKeychainStore: KeychainStore {
    private let storage: OSAllocatedUnfairLock<[String: Data]>

    /// Creates a store that starts with `items`.
    ///
    /// - Parameter items: The initial items, by Keychain key. Defaults to none.
    public init(items: [String: Data] = [:]) {
        storage = OSAllocatedUnfairLock(initialState: items)
    }

    /// A snapshot of every item currently stored.
    public var items: [String: Data] {
        storage.withLock { $0 }
    }

    /// Returns the item stored under `key`, or `nil` when there is none. Never throws.
    public func data(forKey key: String) throws -> Data? {
        storage.withLock { $0[key] }
    }

    /// Stores `data` under `key`, replacing any existing item. Never throws.
    public func set(_ data: Data, forKey key: String) throws {
        storage.withLock { $0[key] = data }
    }

    /// Removes the item stored under `key`, if any. Never throws.
    public func remove(forKey key: String) throws {
        _ = storage.withLock { $0.removeValue(forKey: key) }
    }
}
