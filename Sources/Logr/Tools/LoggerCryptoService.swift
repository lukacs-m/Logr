//
//  LoggerCryptoService.swift
//  Logr
//
//  Created by martin on 02/11/2025.
//

import CryptoKit
import Foundation
import Security
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
    /// - Throws: Keychain access errors. Throw `KeychainError.status(errSecInteractionNotAllowed)` while the
    ///   Keychain is locked, so ``LoggerCryptoService`` reports
    ///   ``LoggerCryptoError/keyTemporarilyUnavailable`` and never mistakes the lock for a missing key.
    func data(forKey key: String) throws -> Data?

    /// Stores data in the keychain.
    ///
    /// - Parameters:
    ///   - data: The data to store.
    ///   - key: The keychain key.
    /// - Throws: Keychain access errors.
    func set(_ data: Data, forKey key: String) throws

    /// Stores data in the keychain unless an item already exists for `key`.
    ///
    /// Checking and storing must be one atomic step (`SecItemAdd` reports `errSecDuplicateItem`): it is what keeps
    /// two services that create a key at the same moment from replacing each other's key.
    ///
    /// - Parameters:
    ///   - data: The data to store.
    ///   - key: The keychain key.
    /// - Returns: `true` if `data` was stored, `false` if an item already existed; that item is left unchanged.
    /// - Throws: Keychain access errors.
    func add(_ data: Data, forKey key: String) throws -> Bool

    /// Removes data from the keychain.
    ///
    /// - Parameter key: The keychain key.
    /// - Throws: Keychain access errors.
    func remove(forKey key: String) throws
}

/// The Logr 1.x Keychain store, which wrapped the KeychainAccess package.
@available(*, deprecated, renamed: "SystemKeychainStore")
public typealias KeychainAccessStore = SystemKeychainStore

// MARK: - LoggerCryptoError

/// Errors that can occur during encryption/decryption operations.
public enum LoggerCryptoError: Error, Equatable {
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

    /// The key cannot be read yet, typically because the Keychain is locked until the device's first unlock after
    /// a restart. A later call succeeds.
    ///
    /// Custom ``LoggerCryptoServicing`` implementations throw it for the same situation: ``LogR`` then keeps
    /// entries in memory and retries, instead of dropping them.
    case keyTemporarilyUnavailable

    /// The stored key version record cannot be decoded or holds a version outside 1...1,000,000.
    ///
    /// No key is created over it, since the stored keys may still decrypt earlier entries; decryption keeps
    /// working. The service reads the record once: create a new service after repairing it.
    case corruptKeyVersion
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
/// let logger = LogR(storage: .sqlite(), cryptoService: MyCustomCrypto())
/// ```
///
/// ## Topics
///
/// ### Encryption Operations
/// - ``symmetricEncrypt(object:)``
/// - ``symmetricDecrypt(encryptedData:)``
/// - ``privacyHashKey()``
public protocol LoggerCryptoServicing: Sendable {
    /// Encrypts a codable object for secure storage.
    ///
    /// The object is first encoded to JSON, then encrypted with the configured algorithm
    /// (AES-256-GCM by default).
    /// The result includes a versioned envelope for key rotation support.
    ///
    /// - Parameter object: The object to encrypt.
    /// - Returns: Encrypted data ready for storage.
    /// ``LogR`` also encrypts a small probe value (`true`) before it writes, to learn whether the key can be read;
    /// the result is discarded.
    ///
    /// - Throws: ``LoggerCryptoError`` if encryption fails; ``LoggerCryptoError/keyTemporarilyUnavailable``
    ///   when the key cannot be read yet, so ``LogR`` retries later.
    func symmetricEncrypt(object: some Codable & Sendable) throws -> Data

    /// Decrypts encrypted data back to the original object.
    ///
    /// Supports multiple key versions for seamless key rotation. The encrypted
    /// data includes the key version used for encryption.
    ///
    /// - Parameter encryptedData: The encrypted data.
    /// - Returns: The decrypted object.
    /// - Throws: ``LoggerCryptoError`` if decryption fails or the key is not found;
    ///   ``LoggerCryptoError/keyTemporarilyUnavailable`` when the key cannot be read yet.
    func symmetricDecrypt<T: Codable & Sendable>(encryptedData: Data) throws -> T

    /// The key ``LogR`` hashes ``LogPrivacy/Mask/hash`` values with, or `nil` when the service has none; those
    /// values then render as `<private>`.
    ///
    /// Derive it from your encryption key rather than returning that key. ``LogR`` asks when it starts opening
    /// storage, again on each retry while this throws ``LoggerCryptoError/keyTemporarilyUnavailable``, and keeps
    /// the first other answer for the launch. The default implementation returns `nil`.
    ///
    /// - Throws: ``LoggerCryptoError/keyTemporarilyUnavailable`` when the key cannot be read yet.
    func privacyHashKey() throws -> SymmetricKey?
}

public extension LoggerCryptoServicing {
    /// No hashing: ``LogPrivacy/Mask/hash`` values render as `<private>`.
    func privacyHashKey() throws -> SymmetricKey? {
        nil
    }
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
    /// Older versions are being or have been removed by a rotation; set and read under `currentKeyVersion`'s lock.
    private let oldestKeptVersion = SafeMutex<Int>(1)
    private let encryptionAlgo: CryptoAlgo

    /// `nil` until the first encryption or rotation reads the version record from the store.
    let currentKeyVersion: SafeMutex<KeyVersion?> = .init(nil)
    /// Set, under `currentKeyVersion`'s lock, once reading or creating the version record failed for any reason
    /// but the locked Keychain; thrown again by every later resolution.
    private let resolutionFailure = SafeMutex<(any Error)?>(nil)

    /// The envelope Logr 1.x wrote: JSON, with the sealed box in base64. Read only.
    ///
    /// Decoding is tolerant of envelopes written before the `algorithm` field existed: those
    /// were always ChaCha20-Poly1305, so an absent `algorithm` key decodes as `.chacha` rather
    /// than failing. This keeps logs persisted by earlier versions readable after an upgrade.
    private struct LegacyEnvelope: Decodable {
        let version: Int
        let data: Data
        let algorithm: CryptoAlgo

        enum CodingKeys: String, CodingKey {
            case version, data, algorithm
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

    /// Creates a service that reads its keys from `store` when it first needs them, so creating it never touches
    /// the Keychain.
    ///
    /// Encryption and rotation read the current key version on first use. While the Keychain is locked they throw
    /// ``LoggerCryptoError/keyTemporarilyUnavailable`` and read it again on the next call, so a service created
    /// before the device's first unlock starts working once the Keychain can be read. Any other failure to read
    /// or create the version record is final for this service: later calls throw it again without asking the
    /// store.
    ///
    /// A key found in the store is never replaced. Version 1 is created only when the store holds no version
    /// record (an existing key 1 is adopted). A record that cannot be decoded, or holds a version outside
    /// 1...1,000,000, makes encryption and rotation throw ``LoggerCryptoError/corruptKeyVersion`` rather than
    /// create a key over the one that encrypted earlier logs.
    ///
    /// - Parameters:
    ///   - store: Where keys live. Defaults to the Keychain, device-only and not synchronized.
    ///   - encryptionAlgo: The cipher for new entries. Defaults to AES-256-GCM. Decryption reads the
    ///     cipher from each entry, so changing it keeps earlier entries readable.
    public init(store: any KeychainStore = SystemKeychainStore(),
                encryptionAlgo: CryptoAlgo = .aes256gcm) {
        self.store = store
        self.encryptionAlgo = encryptionAlgo
    }

    /// Encrypts with a consistent key/version snapshot, even when rotation overlaps encoding.
    public func symmetricEncrypt(object: some Codable) throws -> Data {
        let (version, symmetricKey) = try currentKey()

        // Caller-supplied encoders may reenter this service; never invoke them under the key lock.
        let payload = try encoder.encode(object)
        let encryptedPayload = try symmetricKey.encrypt(payload, algo: encryptionAlgo)

        return Envelope.seal(encryptedPayload, keyVersion: version.value, algorithm: encryptionAlgo)
    }

    /// Decrypts the binary envelope ``symmetricEncrypt(object:)`` writes, and the JSON envelope of Logr 1.x.
    public func symmetricDecrypt<T: Codable & Sendable>(encryptedData: Data) throws -> T {
        let envelope = try open(encryptedData)

        let version = KeyVersion(envelope.keyVersion)
        let key = try withKeychain { try currentKeyVersion.withLock { _ in try loadKey(version: version) } }
        guard let symmetricKey = key else {
            throw LoggerCryptoError.keyNotFound(version: version.value)
        }

        let decryptedData = try symmetricKey.decrypt(envelope.sealedBox, algo: envelope.algorithm)
        return try decoder.decode(T.self, from: decryptedData)
    }

    /// An HKDF-SHA256 derivation of the current encryption key, so hashes made with it do not expose the key. It
    /// changes when the key is rotated.
    public func privacyHashKey() throws -> SymmetricKey? {
        let (_, key) = try currentKey()
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: key, info: Data("Logr privacy hash".utf8),
                                      outputByteCount: keySize)
    }

    // MARK: - Rotation

    /// Serializes rotations within this service. Retained keys keep earlier entries readable.
    ///
    /// A key already stored for the next version is adopted rather than replaced. With
    /// `removeOldKeys`, every older key version is removed, so all entries encrypted before the
    /// rotation become unreadable, including in-flight encryptions that already selected an older
    /// key. If removal fails, the new key remains active and the removal error is thrown
    /// (``LoggerCryptoError/keyTemporarilyUnavailable`` when the Keychain is locked).
    ///
    /// Versions stop at 1,000,000: rotating from it throws ``LoggerCryptoError/keychainFailure(_:)`` and
    /// keeps the current key.
    public func rotateKey(removeOldKeys: Bool = false) throws {
        try withKeychain { try rotate(removeOldKeys: removeOldKeys) }
    }
}

// MARK: - Private Helpers

private extension LoggerCryptoService {
    func currentKey() throws -> (KeyVersion, SymmetricKey) {
        try withKeychain {
            try currentKeyVersion.withLock { version in
                let current = try resolve(&version)
                guard let key = try loadKey(version: current) else {
                    throw LoggerCryptoError.keyNotFound(version: current.value)
                }
                return (current, key)
            }
        }
    }

    func rotate(removeOldKeys: Bool) throws {
        let newVersion = try currentKeyVersion.withLock { version in
            let current = try resolve(&version)
            guard current.value < maxKeyVersion else {
                throw LoggerCryptoError.keychainFailure("Key version \(maxKeyVersion) is the last; cannot rotate")
            }
            let newVersion = KeyVersion(current.value + 1)
            let newKey = try Self.loadOrCreateKey(version: newVersion, store: store, keyPrefix: keyPrefix,
                                                  keySize: keySize)
            try store.set(encoder.encode(newVersion), forKey: currentKeyRef)
            cacheKeys.withLock { cache in
                cache[newVersion] = newKey
                if removeOldKeys {
                    cache = cache.filter { $0.key == newVersion }
                }
            }
            if removeOldKeys {
                oldestKeptVersion.withLock { $0 = newVersion.value }
            }
            version = newVersion
            return newVersion
        }
        guard removeOldKeys else { return }
        // Off the lock: every encryption and decryption takes it, and this costs up to two Keychain calls
        // for each older version.
        for value in 1..<newVersion.value {
            let name = keyName(for: KeyVersion(value))
            // Earlier rotations already removed most versions; custom stores may throw for those.
            guard try store.data(forKey: name) != nil else { continue }
            try store.remove(forKey: name)
        }
    }

    /// Reports a Keychain that cannot be read before the first unlock as
    /// ``LoggerCryptoError/keyTemporarilyUnavailable``.
    func withKeychain<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch where Self.isKeychainLock(error) {
            throw LoggerCryptoError.keyTemporarilyUnavailable
        }
    }

    /// The documented ``KeychainError`` or Logr's own error, or the status as an `NSError`, which stores ported
    /// from Logr 1.x (KeychainAccess) throw.
    static func isKeychainLock(_ error: any Error) -> Bool {
        switch error {
        case KeychainError.status(errSecInteractionNotAllowed), LoggerCryptoError.keyTemporarilyUnavailable:
            true
        default:
            (error as NSError).code == Int(errSecInteractionNotAllowed)
        }
    }

    /// Returns the current key version, reading it from the store the first time; creates version 1 only when
    /// the store has no version record. Called with `currentKeyVersion`'s lock held.
    func resolve(_ version: inout KeyVersion?) throws -> KeyVersion {
        if let version {
            return version
        }
        if let failure = resolutionFailure.value {
            throw failure
        }
        do {
            let resolved: KeyVersion
            if let record = try store.data(forKey: currentKeyRef) {
                guard let decoded = try? decoder.decode(KeyVersion.self, from: record),
                      (1...maxKeyVersion).contains(decoded.value)
                else {
                    throw LoggerCryptoError.corruptKeyVersion
                }
                resolved = decoded
            } else {
                resolved = .default
                let key = try Self.loadOrCreateKey(version: resolved, store: store, keyPrefix: keyPrefix,
                                                   keySize: keySize)
                try store.set(encoder.encode(resolved), forKey: currentKeyRef)
                cacheKeys.withLock { $0[resolved] = key }
            }
            version = resolved
            return resolved
        } catch {
            // Only the lock lifts by itself. As when Logr 1.x read the record in its init, any other failure is
            // final, so a Keychain that keeps failing is not asked again for every entry.
            if !Self.isKeychainLock(error) {
                resolutionFailure.withLock { $0 = error }
            }
            throw error
        }
    }

    func open(_ data: Data) throws -> Envelope {
        guard data.first == UInt8(ascii: "{") else { return try Envelope(data) }
        let legacy = try decoder.decode(LegacyEnvelope.self, from: data)
        return Envelope(keyVersion: legacy.version, algorithm: legacy.algorithm, sealedBox: legacy.data)
    }

    func keyName(for version: KeyVersion) -> String {
        "\(keyPrefix)\(version.value)"
    }

    func loadKey(version: KeyVersion) throws -> SymmetricKey? {
        // A rotation may still be removing this version from the store; it must not come back into the cache.
        guard version.value >= oldestKeptVersion.value else { return nil }
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

    /// Returns the stored key for `version`, generating and adding one only when none exists, so a key
    /// that may have encrypted entries is never replaced.
    static func loadOrCreateKey(version: KeyVersion,
                                store: any KeychainStore,
                                keyPrefix: String,
                                keySize: Int) throws -> SymmetricKey {
        let name = "\(keyPrefix)\(version.value)"
        if let existing = try store.data(forKey: name) {
            return SymmetricKey(data: existing)
        }
        let data = try Data.randomBytes(count: keySize)
        if try store.add(data, forKey: name) {
            return SymmetricKey(data: data)
        }
        // Another service stored a key between the read and the add: that key wins.
        guard let stored = try store.data(forKey: name) else {
            throw LoggerCryptoError.keychainFailure("Key \(name) was added by another service and then removed")
        }
        return SymmetricKey(data: stored)
    }
}

// MARK: - Envelope

/// The binary envelope: a magic byte, the format version (2), the cipher, the key version as a big-endian
/// `UInt32`, then the sealed box (nonce, ciphertext and tag). Logr 1.x wrote JSON instead, which starts with `{`.
private struct Envelope {
    private static let magic: UInt8 = 0xC5
    private static let formatVersion: UInt8 = 2
    private static let headerLength = 7

    let keyVersion: Int
    let algorithm: LoggerCryptoService.CryptoAlgo
    let sealedBox: Data

    init(keyVersion: Int, algorithm: LoggerCryptoService.CryptoAlgo, sealedBox: Data) {
        self.keyVersion = keyVersion
        self.algorithm = algorithm
        self.sealedBox = sealedBox
    }

    /// - Throws: ``LoggerCryptoError/invalidEnvelope`` for anything but a version 2 envelope.
    init(_ data: Data) throws {
        // `Array` so the header is indexed from 0 even when `data` is a slice.
        let header = [UInt8](data.prefix(Self.headerLength))
        guard data.count > Self.headerLength, header[0] == Self.magic, header[1] == Self.formatVersion,
              let algorithm = LoggerCryptoService.CryptoAlgo(envelopeByte: header[2])
        else {
            throw LoggerCryptoError.invalidEnvelope
        }
        keyVersion = header[3...].reduce(0) { $0 << 8 | Int($1) }
        self.algorithm = algorithm
        sealedBox = Data(data.dropFirst(Self.headerLength))
    }

    static func seal(_ sealedBox: Data, keyVersion: Int, algorithm: LoggerCryptoService.CryptoAlgo) -> Data {
        var data = Data(capacity: headerLength + sealedBox.count)
        data.append(contentsOf: [magic, formatVersion, algorithm.envelopeByte])
        withUnsafeBytes(of: UInt32(keyVersion).bigEndian) { data.append(contentsOf: $0) }
        data.append(sealedBox)
        return data
    }
}

private extension LoggerCryptoService.CryptoAlgo {
    var envelopeByte: UInt8 {
        switch self {
        case .chacha: 1
        case .aes256gcm: 2
        }
    }

    init?(envelopeByte: UInt8) {
        switch envelopeByte {
        case 1: self = .chacha
        case 2: self = .aes256gcm
        default: return nil
        }
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
