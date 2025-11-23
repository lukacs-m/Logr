//
//  LoggerCryptoService.swift
//  Logr
//
//  Created by martin on 02/11/2025.
//

import CryptoKit
import Foundation
@preconcurrency import KeychainAccess
import Synchronization

// MARK: - Protocol: KeychainStore

/// Protocol for secure keychain storage operations.
///
/// Abstracts keychain operations to allow for testing and custom implementations.
public protocol KeychainStore: Sendable {
    /// Retrieves data from the keychain.
    ///
    /// - Parameter key: The keychain key.
    /// - Returns: The stored data, or `nil` if not found.
    /// - Throws: Keychain access errors.
    func data(forKey key: String) throws -> Data?

    /// Stores data in the keychain.
    ///
    /// - Parameters:
    ///   - data: The data to store.
    ///   - key: The keychain key.
    /// - Throws: Keychain access errors.
    func set(_ data: Data, forKey key: String) throws

    /// Removes data from the keychain.
    ///
    /// - Parameter key: The keychain key.
    /// - Throws: Keychain access errors.
    func remove(forKey key: String) throws
}

// MARK: - Production Implementation using KeychainAccess

public struct KeychainAccessStore: KeychainStore {
    private let keychain: Keychain

    public init(service: String, accessGroup: String? = nil) {
        let keychain = if let accessGroup {
            Keychain(service: service, accessGroup: accessGroup)
        } else {
            Keychain(service: service)
        }
        self.keychain = keychain.accessibility(.whenUnlockedThisDeviceOnly)
            .synchronizable(false)
    }

    public func data(forKey key: String) throws -> Data? {
        try keychain.getData(key)
    }

    public func set(_ data: Data, forKey key: String) throws {
        try keychain.set(data, key: key)
    }

    public func remove(forKey key: String) throws {
        try keychain.remove(key)
    }
}

// MARK: - LoggerCryptoError

/// Errors that can occur during encryption/decryption operations.
public enum LoggerCryptoError: Error {
    /// The encryption key for the specified version was not found.
    case keyNotFound(version: Int)

    /// A keychain operation failed.
    case keychainFailure(String)

    /// Encryption operation failed.
    case encryptionFailed

    /// Decryption operation failed.
    case decryptionFailed

    /// The encrypted data envelope is invalid or corrupted.
    case invalidEnvelope
}

// MARK: - KeyVersion

public struct KeyVersion: Codable, Sendable, Hashable {
    public let value: Int
    public init(_ value: Int) { self.value = value }

    static var `default`: KeyVersion {
        KeyVersion(1)
    }
}

/// Protocol for encrypting and decrypting log entries.
///
/// `LoggerCryptoServicing` defines the interface for secure log encryption.
/// The default implementation uses ChaCha20-Poly1305 encryption with keys stored
/// in the Keychain.
///
/// ## Overview
///
/// All log entries are automatically encrypted before persistent storage.
/// Encryption keys are:
/// - Generated automatically on first use
/// - Stored securely in the Keychain
/// - Versioned to support key rotation
/// - Never exposed outside the crypto service
///
/// ## Example Custom Implementation
///
/// ```swift
/// class MyCustomCrypto: LoggerCryptoServicing {
///     func symmetricEncrypt<T: Codable>(object: T) throws -> Data {
///         // Your custom encryption
///         return encryptedData
///     }
///
///     func symmetricDecrypt<T: Codable>(encryptedData: Data) throws -> T {
///         // Your custom decryption
///         return decryptedObject
///     }
/// }
///
/// let logger = LogR(
///     storage: SQLiteStorage(),
///     cryptoService: MyCustomCrypto()
/// )
/// ```
///
/// ## Topics
///
/// ### Encryption Operations
/// - ``symmetricEncrypt(object:)``
/// - ``symmetricDecrypt(encryptedData:)``
public protocol LoggerCryptoServicing: Sendable {
    /// Encrypts a codable object for secure storage.
    ///
    /// The object is first encoded to JSON, then encrypted using ChaCha20-Poly1305.
    /// The result includes a versioned envelope for key rotation support.
    ///
    /// - Parameter object: The object to encrypt.
    /// - Returns: Encrypted data ready for storage.
    /// - Throws: ``LoggerCryptoError`` if encryption fails.
    func symmetricEncrypt(object: some Codable & Sendable) throws -> Data

    /// Decrypts encrypted data back to the original object.
    ///
    /// Supports multiple key versions for seamless key rotation. The encrypted
    /// data includes the key version used for encryption.
    ///
    /// - Parameter encryptedData: The encrypted data.
    /// - Returns: The decrypted object.
    /// - Throws: ``LoggerCryptoError`` if decryption fails or the key is not found.
    func symmetricDecrypt<T: Codable & Sendable>(encryptedData: Data) throws -> T
}

// MARK: - Actor: LoggerCryptoService

public final class LoggerCryptoService: Sendable, LoggerCryptoServicing {
    private let store: KeychainStore
    private let currentKeyRef = "logger_current_key_version"
    private let keyPrefix = "logger_sym_key_v"
    private let keySize = 32 // 256 bits
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let cacheKeys: any MutexProtected<[KeyVersion: SymmetricKey]> = SafeMutex.create([:])

    let currentVersion: any MutexProtected<KeyVersion> = SafeMutex.create(.default)

    /// Private envelope to store encrypted data with key version
    private struct CryptoEnvelope: Codable {
        let version: Int
        let data: Data
    }

    // MARK: - Init

    public init(store: KeychainStore = KeychainAccessStore(service: "com.logr.KeychainStore")) {
        self.store = store
        if let versionData = try? store.data(forKey: currentKeyRef),
           let version = try? decoder.decode(KeyVersion.self, from: versionData) {
            currentVersion.modify {
                $0 = version
            }
        } else {
            do {
                let newKeyVersion = KeyVersion.default
                let key = try Self.generateKey(version: newKeyVersion, store: store, keyPrefix: keyPrefix,
                                               keySize: keySize)
                try store.set(encoder.encode(newKeyVersion), forKey: currentKeyRef)
                currentVersion.modify {
                    $0 = newKeyVersion
                }
                cacheKeys.modify {
                    $0[newKeyVersion] = key
                }
            } catch {
                fatalError("Failed to generate initial key with error \(error.localizedDescription)")
            }
        }
    }

    public func symmetricEncrypt(object: some Codable) throws -> Data {
        guard let symmetricKey = try loadKey(version: currentVersion.value) else {
            throw LoggerCryptoError.keyNotFound(version: currentVersion.value.value)
        }

        let payload = try encoder.encode(object)
        let encryptedPayload = try symmetricKey.encrypt(payload)

        let envelope = CryptoEnvelope(version: currentVersion.value.value, data: encryptedPayload)
        return try encoder.encode(envelope)
    }

    public func symmetricDecrypt<T: Codable & Sendable>(encryptedData: Data) throws -> T {
        let envelope = try decoder.decode(CryptoEnvelope.self, from: encryptedData)

        let version = KeyVersion(envelope.version)
        guard let symmetricKey = try loadKey(version: version) else {
            throw LoggerCryptoError.keyNotFound(version: version.value)
        }

        let decryptedData = try symmetricKey.decrypt(envelope.data)
        return try decoder.decode(T.self, from: decryptedData)
    }

    // MARK: - Rotation

    public func rotateKey(removeOldKeys: Bool = false) throws {
        let newVersion = KeyVersion(currentVersion.value.value + 1)
        let newKey = try Self.generateKey(version: newVersion, store: store, keyPrefix: keyPrefix,
                                          keySize: keySize)
        try store.set(encoder.encode(newVersion), forKey: currentKeyRef)
        if removeOldKeys {
            try? store.remove(forKey: keyName(for: currentVersion.value))
            cacheKeys.modify {
                $0.removeValue(forKey: currentVersion.value)
            }
        }
        currentVersion.modify {
            $0 = newVersion
        }
        cacheKeys.modify {
            $0[newVersion] = newKey
        }
    }
}

// MARK: - Private Helpers

private extension LoggerCryptoService {
    func keyName(for version: KeyVersion) -> String {
        "\(keyPrefix)\(version.value)"
    }

    func loadKey(version: KeyVersion) throws -> SymmetricKey? {
        if let key = cacheKeys.value[version] {
            return key
        }
        guard let keyData = try store.data(forKey: keyName(for: version)) else {
            return nil
        }
        let symmetricKey = SymmetricKey(data: keyData)
        cacheKeys.modify {
            $0[version] = symmetricKey
        }
        return symmetricKey
    }

    static func generateKey(version: KeyVersion,
                            store: KeychainStore,
                            keyPrefix: String,
                            keySize: Int) throws -> SymmetricKey {
        let data = Data.randomBytes(count: keySize)
        try store.set(data, forKey: "\(keyPrefix)\(version.value)")
        return SymmetricKey(data: data)
    }
}

// MARK: - Data helpers

private extension Data {
    static func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }
}

private extension SymmetricKey {
    func encrypt(_ clearData: Data) throws -> Data {
        try ChaChaPoly.seal(clearData, using: self).combined
    }

    func decrypt(_ cypherData: Data) throws -> Data {
        let sealedBox = try ChaChaPoly.SealedBox(combined: cypherData)
        return try ChaChaPoly.open(sealedBox, using: self)
    }
}
