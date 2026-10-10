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
        self.keychain = keychain.accessibility(.afterFirstUnlockThisDeviceOnly)
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
    case initializationFailed(underlying: any Error)
}

// MARK: - KeyVersion

public struct KeyVersion: Codable, Sendable, Hashable {
    public let value: Int
    public init(_ value: Int) {
        self.value = value
    }

    static var `default`: KeyVersion {
        KeyVersion(1)
    }
}

/// Protocol for encrypting and decrypting log entries.
///
/// `LoggerCryptoServicing` defines the interface for secure log encryption.
/// The default implementation, ``LoggerCryptoService``, uses AES-256-GCM by default
/// (ChaCha20-Poly1305 selectable via `encryptionAlgo: .chacha`) with keys stored
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
/// struct MyCustomCrypto: LoggerCryptoServicing {   // Sendable — use a struct
///     func symmetricEncrypt(object: some Codable & Sendable) throws -> Data {
///         // Your custom encryption
///         return encryptedData
///     }
///
///     func symmetricDecrypt<T: Codable & Sendable>(encryptedData: Data) throws -> T {
///         // Your custom decryption
///         return decryptedObject
///     }
/// }
///
/// // `try` is for SQLiteStorage(); this LogR overload does not throw
/// let logger = try LogR(
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
    /// The object is first encoded to JSON, then encrypted with the configured algorithm
    /// (AES-256-GCM by default).
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
    private let store: any KeychainStore
    private let currentKeyRef = "logger_current_key_version"
    private let keyPrefix = "logger_sym_key_v"
    private let keySize = 32 // 256 bits
    /// Far beyond any real rotation count; a larger stored version can only come from a damaged record.
    private let maxKeyVersion = 1_000_000
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let cacheKeys: SafeMutex<[KeyVersion: SymmetricKey]> = .init([:])
    private let encryptionAlgo: CryptoAlgo

    let currentKeyVersion: SafeMutex<KeyVersion> = .init(.default)

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

        init(from decoder: any Decoder) throws {
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

    /// Loads the current key version from `store`, creating key version 1 only on a true first run.
    ///
    /// A key found in the store is never replaced: a failed Keychain read, or a version record that cannot
    /// be decoded or holds a version outside 1...1,000,000, throws
    /// ``LoggerCryptoError/initializationFailed(underlying:)`` (wrapping the read error or a `DecodingError`)
    /// instead of provisioning a new key over the one that encrypted earlier logs. When key version 1 exists
    /// without a version record, that key is adopted.
    ///
    /// - Parameters:
    ///   - store: Where keys live. Defaults to the Keychain, device-only and not synchronized.
    ///   - encryptionAlgo: The cipher for new entries. Defaults to AES-256-GCM. Decryption reads the
    ///     cipher from each entry, so changing it keeps earlier entries readable.
    /// - Throws: ``LoggerCryptoError/initializationFailed(underlying:)``.
    public init(store: any KeychainStore = KeychainAccessStore(service: "com.logr.KeychainStore"),
                encryptionAlgo: CryptoAlgo = .aes256gcm) throws {
        self.store = store
        self.encryptionAlgo = encryptionAlgo
        do {
            // A failed read (e.g. keychain locked during a background launch) is not "first run".
            if let versionData = try store.data(forKey: currentKeyRef) {
                let version = try decoder.decode(KeyVersion.self, from: versionData)
                guard (1...maxKeyVersion).contains(version.value) else {
                    let reason = "Key version \(version.value) is outside 1...\(maxKeyVersion)"
                    throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: reason))
                }
                currentKeyVersion.withLock { $0 = version }
                return
            }
            let firstVersion = KeyVersion.default
            let key = try Self.loadOrCreateKey(version: firstVersion, store: store, keyPrefix: keyPrefix,
                                               keySize: keySize)
            try store.set(encoder.encode(firstVersion), forKey: currentKeyRef)
            currentKeyVersion.withLock { $0 = firstVersion }
            cacheKeys.withLock { $0[firstVersion] = key }
        } catch {
            throw LoggerCryptoError.initializationFailed(underlying: error)
        }
    }

    /// Encrypts with a consistent key/version snapshot, even when rotation overlaps encoding.
    public func symmetricEncrypt(object: some Codable) throws -> Data {
        let (version, symmetricKey) = try currentKeyVersion.withLock { version in
            guard let key = try loadKey(version: version) else {
                throw LoggerCryptoError.keyNotFound(version: version.value)
            }
            return (version, key)
        }

        // Caller-supplied encoders may reenter this service; never invoke them under the key lock.
        let payload = try encoder.encode(object)
        let encryptedPayload = try symmetricKey.encrypt(payload, algo: encryptionAlgo)

        let envelope = CryptoEnvelope(version: version.value, data: encryptedPayload,
                                      algorithm: encryptionAlgo)
        return try encoder.encode(envelope)
    }

    public func symmetricDecrypt<T: Codable & Sendable>(encryptedData: Data) throws -> T {
        let envelope = try decoder.decode(CryptoEnvelope.self, from: encryptedData)

        let version = KeyVersion(envelope.version)
        let key = try currentKeyVersion.withLock { _ in try loadKey(version: version) }
        guard let symmetricKey = key else {
            throw LoggerCryptoError.keyNotFound(version: version.value)
        }

        let decryptedData = try symmetricKey.decrypt(envelope.data, algo: envelope.algorithm)
        return try decoder.decode(T.self, from: decryptedData)
    }

    // MARK: - Rotation

    /// Serializes rotations within this service. Retained keys keep earlier entries readable.
    ///
    /// A key already stored for the next version is adopted rather than replaced. With
    /// `removeOldKeys`, every older key version is removed, so all entries encrypted before the
    /// rotation become unreadable, including in-flight encryptions that already selected an older
    /// key. If removal fails, the new key remains active and the removal error is thrown.
    ///
    /// Versions stop at 1,000,000: rotating from it throws ``LoggerCryptoError/keychainFailure(_:)`` and
    /// keeps the current key.
    public func rotateKey(removeOldKeys: Bool = false) throws {
        try currentKeyVersion.withLock { version in
            guard version.value < maxKeyVersion else {
                throw LoggerCryptoError.keychainFailure("Key version \(maxKeyVersion) is the last; cannot rotate")
            }
            let newVersion = KeyVersion(version.value + 1)
            let newKey = try Self.loadOrCreateKey(version: newVersion, store: store, keyPrefix: keyPrefix,
                                                  keySize: keySize)
            try store.set(encoder.encode(newVersion), forKey: currentKeyRef)
            cacheKeys.withLock { $0[newVersion] = newKey }
            version = newVersion
            if removeOldKeys {
                for value in 1..<newVersion.value {
                    let oldVersion = KeyVersion(value)
                    _ = cacheKeys.withLock { $0.removeValue(forKey: oldVersion) }
                    // Earlier rotations already removed most versions; custom stores may throw for those.
                    guard try store.data(forKey: keyName(for: oldVersion)) != nil else { continue }
                    try store.remove(forKey: keyName(for: oldVersion))
                }
            }
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
        cacheKeys.withLock {
            $0[version] = symmetricKey
        }
        return symmetricKey
    }

    /// Returns the stored key for `version`, generating and storing one only when none exists, so a key
    /// that may have encrypted entries is never replaced. The read and the add are separate calls: two
    /// services provisioning the same store at the same moment can still both add.
    static func loadOrCreateKey(version: KeyVersion,
                                store: any KeychainStore,
                                keyPrefix: String,
                                keySize: Int) throws -> SymmetricKey {
        let name = "\(keyPrefix)\(version.value)"
        if let existing = try store.data(forKey: name) {
            return SymmetricKey(data: existing)
        }
        let data = try Data.randomBytes(count: keySize)
        try store.set(data, forKey: name)
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
