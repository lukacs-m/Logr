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

    /// Initialization failed due to an underlying error.
    case initializationFailed(underlying: Error)
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
    private let encryptionAlgo: CryptoAlgo

    let currentKeyVersion: any MutexProtected<KeyVersion> = SafeMutex.create(.default)

    /// Private envelope to store encrypted data with key version.
    ///
    /// Decoding is tolerant of envelopes written before the `algorithm` field existed: those
    /// were always ChaCha20-Poly1305, so an absent `algorithm` key decodes as `.chacha` rather
    /// than failing. This keeps logs persisted by earlier versions readable after an upgrade.
    private struct CryptoEnvelope: Codable {
        let version: Int
        let data: Data
        let algorithm: CryptoAlgo

        enum CodingKeys: String, CodingKey {
            case version, data, algorithm
        }

        init(version: Int, data: Data, algorithm: CryptoAlgo) {
            self.version = version
            self.data = data
            self.algorithm = algorithm
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(Int.self, forKey: .version)
            data = try container.decode(Data.self, forKey: .data)
            // Legacy envelopes predate the algorithm field and were always ChaCha20-Poly1305.
            algorithm = try container.decodeIfPresent(CryptoAlgo.self, forKey: .algorithm) ?? .chacha
        }
    }

    public enum CryptoAlgo: Sendable, Codable {
        case chacha
        case aes256gcm
    }

    // MARK: - Init

    public init(store: KeychainStore = KeychainAccessStore(service: "com.logr.KeychainStore"),
                encryptionAlgo: CryptoAlgo = .aes256gcm) throws {
        self.store = store
        self.encryptionAlgo = encryptionAlgo
        if let versionData = try? store.data(forKey: currentKeyRef),
           let version = try? decoder.decode(KeyVersion.self, from: versionData) {
            currentKeyVersion.modify {
                $0 = version
            }
        } else {
            do {
                let newKeyVersion = KeyVersion.default
                let key = try Self.generateKey(version: newKeyVersion, store: store, keyPrefix: keyPrefix,
                                               keySize: keySize)
                try store.set(encoder.encode(newKeyVersion), forKey: currentKeyRef)
                currentKeyVersion.modify {
                    $0 = newKeyVersion
                }
                cacheKeys.modify {
                    $0[newKeyVersion] = key
                }
            } catch {
                throw LoggerCryptoError.initializationFailed(underlying: error)
            }
        }
    }

    public func symmetricEncrypt(object: some Codable) throws -> Data {
        guard let symmetricKey = try loadKey(version: currentKeyVersion.value) else {
            throw LoggerCryptoError.keyNotFound(version: currentKeyVersion.value.value)
        }

        let payload = try encoder.encode(object)
        let encryptedPayload = try symmetricKey.encrypt(payload, algo: encryptionAlgo)

        let envelope = CryptoEnvelope(version: currentKeyVersion.value.value, data: encryptedPayload,
                                      algorithm: encryptionAlgo)
        return try encoder.encode(envelope)
    }

    public func symmetricDecrypt<T: Codable & Sendable>(encryptedData: Data) throws -> T {
        let envelope = try decoder.decode(CryptoEnvelope.self, from: encryptedData)

        let version = KeyVersion(envelope.version)
        guard let symmetricKey = try loadKey(version: version) else {
            throw LoggerCryptoError.keyNotFound(version: version.value)
        }

        let decryptedData = try symmetricKey.decrypt(envelope.data, algo: envelope.algorithm)
        return try decoder.decode(T.self, from: decryptedData)
    }

    // MARK: - Rotation

    public func rotateKey(removeOldKeys: Bool = false) throws {
        let newVersion = KeyVersion(currentKeyVersion.value.value + 1)
        let newKey = try Self.generateKey(version: newVersion, store: store, keyPrefix: keyPrefix,
                                          keySize: keySize)
        try store.set(encoder.encode(newVersion), forKey: currentKeyRef)
        if removeOldKeys {
            try? store.remove(forKey: keyName(for: currentKeyVersion.value))
            cacheKeys.modify {
                $0.removeValue(forKey: currentKeyVersion.value)
            }
        }
        currentKeyVersion.modify {
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
        let data = try Data.randomBytes(count: keySize)
        try store.set(data, forKey: "\(keyPrefix)\(version.value)")
        return SymmetricKey(data: data)
    }
}

// MARK: - Data helpers

private extension Data {
    static func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            throw LoggerCryptoError.keychainFailure("SecRandomCopyBytes failed with status \(status)")
        }
        return Data(bytes)
    }
}

private extension SymmetricKey {
    func encrypt(_ clearData: Data, algo: LoggerCryptoService.CryptoAlgo) throws -> Data {
        switch algo {
        case .chacha:
            // `ChaChaPoly.SealedBox.combined` is non-optional.
            return try ChaChaPoly.seal(clearData, using: self).combined
        case .aes256gcm:
            // `AES.GCM.SealedBox.combined` is `Data?` — non-nil only for a 96-bit nonce, which the
            // nonce-less `seal` always generates. Surface the contract as a throw rather than `nil`.
            guard let combined = try AES.GCM.seal(clearData, using: self).combined else {
                throw LoggerCryptoError.encryptionFailed
            }
            return combined
        }
    }

    func decrypt(_ cypherData: Data, algo: LoggerCryptoService.CryptoAlgo) throws -> Data {
        switch algo {
        case .chacha:
            let sealedBox = try ChaChaPoly.SealedBox(combined: cypherData)
            return try ChaChaPoly.open(sealedBox, using: self)
        case .aes256gcm:
            let sealedBox = try AES.GCM.SealedBox(combined: cypherData)
            return try AES.GCM.open(sealedBox, using: self)
        }
    }
}
