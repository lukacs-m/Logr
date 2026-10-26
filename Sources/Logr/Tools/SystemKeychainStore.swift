//
//  SystemKeychainStore.swift
//  Logr
//

import Foundation
import Security

/// A Keychain failure, carrying the Security framework's result code.
///
/// `.status(errSecInteractionNotAllowed)` (-25308) means the Keychain cannot be read yet, typically before the
/// device's first unlock after a restart.
public enum KeychainError: Error, Equatable, CustomStringConvertible {
    /// The `OSStatus` a Keychain call returned.
    case status(OSStatus)

    public var description: String {
        switch self {
        case let .status(status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
            return "Keychain error \(status): \(message)"
        }
    }
}

/// Stores keys as generic passwords in the Keychain: readable after the device's first unlock, never synchronized,
/// never moved to another device.
///
/// On macOS, items go to the data-protection keychain when the app is entitled to it (its code signature
/// carries an application identifier, which comes with a provisioning profile), and to the user's login
/// keychain otherwise. Logr 1.x always used the login keychain on macOS: a key found only there is copied to
/// the data-protection keychain when read, and ``remove(forKey:)`` removes a key from both. The login keychain
/// is shared by the user's apps, so apps there that use the same `service` see each other's items, and macOS
/// asks the user before one app reads another's.
public struct SystemKeychainStore: KeychainStore {
    private let service: String
    private let accessGroup: String?

    /// Creates a store for the items under `service`.
    ///
    /// - Parameters:
    ///   - service: The Keychain service the items are stored under. Defaults to the one Logr 1.x used.
    ///   - accessGroup: A Keychain access group, to share keys with app extensions. On macOS it applies only
    ///     in the data-protection keychain.
    public init(service: String = "com.logr.KeychainStore", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    /// Returns the item stored under `key`, or `nil` when there is none.
    ///
    /// - Throws: ``KeychainError`` when the Keychain cannot be read, such as `errSecInteractionNotAllowed` before
    ///   the first unlock.
    public func data(forKey key: String) throws -> Data? {
        #if os(macOS)
        do {
            if let data = try read(key, dataProtection: true) {
                return data
            }
        } catch KeychainError.status(errSecMissingEntitlement) {}
        guard let data = try read(key, dataProtection: false) else { return nil }
        // Fails for an app without the entitlement, which keeps reading the login keychain.
        _ = try? insert(data, forKey: key, dataProtection: true)
        return data
        #else
        return try read(key, dataProtection: true)
        #endif
    }

    /// Stores `data` under `key`, replacing any existing item.
    ///
    /// - Throws: ``KeychainError``.
    public func set(_ data: Data, forKey key: String) throws {
        try withLoginKeychainFallback { dataProtection in
            guard try !insert(data, forKey: key, dataProtection: dataProtection) else { return }
            try update(data, forKey: key, dataProtection: dataProtection)
        }
    }

    /// Stores `data` under `key` unless an item already exists there, in one `SecItemAdd` call.
    ///
    /// - Returns: `true` if `data` was stored, `false` if an item already existed; that item is left unchanged.
    /// - Throws: ``KeychainError``.
    public func add(_ data: Data, forKey key: String) throws -> Bool {
        try withLoginKeychainFallback { try insert(data, forKey: key, dataProtection: $0) }
    }

    /// Removes the item stored under `key`, if any.
    ///
    /// - Throws: ``KeychainError``.
    public func remove(forKey key: String) throws {
        #if os(macOS)
        do {
            try delete(key, dataProtection: true)
        } catch KeychainError.status(errSecMissingEntitlement) {}
        // A copy left in the login keychain would be copied back by the next read.
        try delete(key, dataProtection: false)
        #else
        try delete(key, dataProtection: true)
        #endif
    }
}

private extension SystemKeychainStore {
    /// Runs `body` against the data-protection keychain or, on macOS, against the login keychain when the app is
    /// not entitled to the former.
    func withLoginKeychainFallback<T>(_ body: (_ dataProtection: Bool) throws -> T) throws -> T {
        #if os(macOS)
        do {
            return try body(true)
        } catch KeychainError.status(errSecMissingEntitlement) {
            return try body(false)
        }
        #else
        return try body(true)
        #endif
    }

    func query(_ key: String, dataProtection: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        if dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
            if let accessGroup {
                query[kSecAttrAccessGroup as String] = accessGroup
            }
        }
        return query
    }

    func read(_ key: String, dataProtection: Bool) throws -> Data? {
        var query = query(key, dataProtection: dataProtection)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.status(status)
        }
    }

    /// Adds the item; `false` when one already exists.
    func insert(_ data: Data, forKey key: String, dataProtection: Bool) throws -> Bool {
        var attributes = query(key, dataProtection: dataProtection)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return true
        case errSecDuplicateItem:
            return false
        default:
            throw KeychainError.status(status)
        }
    }

    func update(_ data: Data, forKey key: String, dataProtection: Bool) throws {
        let status = SecItemUpdate(query(key, dataProtection: dataProtection) as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    func delete(_ key: String, dataProtection: Bool) throws {
        let status = SecItemDelete(query(key, dataProtection: dataProtection) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }
}
