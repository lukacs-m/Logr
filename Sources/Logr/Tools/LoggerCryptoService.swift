//  
//  LoggerCryptoService.swift
//  Logr
//
//  Created by martin on 02/11/2025.
//

import Foundation
import CryptoKit
@preconcurrency import KeychainAccess
import Synchronization

// MARK: - Protocol: KeychainStore
public protocol KeychainStore: Sendable {
    func data(forKey key: String) throws -> Data?
    func set(_ data: Data, forKey key: String) throws
    func remove(forKey key: String) throws
}

// MARK: - Production Implementation using KeychainAccess
public struct KeychainAccessStore: KeychainStore {
    private let keychain: Keychain

    public init(service: String, accessGroup: String? = nil) {
       let keychain  = if let accessGroup {
            Keychain(service: service, accessGroup: accessGroup)
        } else {
            Keychain(service: service)
        }
        self.keychain = keychain .accessibility(.whenUnlockedThisDeviceOnly)
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
public enum LoggerCryptoError: Error {
    case keyNotFound(version: Int)
    case keychainFailure(String)
    case encryptionFailed
    case decryptionFailed
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

public protocol LoggerCryptoServicing: Sendable {
    func symmetricEncrypt(object: some Codable & Sendable) throws -> Data
    func symmetricDecrypt<T: Codable & Sendable>(encryptedData: Data) throws -> T
}

// MARK: - Actor: LoggerCryptoService
public final class LoggerCryptoService: Sendable, LoggerCryptoServicing {
    private let store: KeychainStore
    private let currentKeyRef = "logger_current_key_version"
    private let keyPrefix = "logger_sym_key_v"
    private let keySize = 32  // 256 bits
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
            self.currentVersion.modify {
                $0 = version
            }
        } else {
            do {
                let newKeyVersion = KeyVersion.default
                let key = try Self.generateKey(version: newKeyVersion, store: store, keyPrefix: keyPrefix, keySize: keySize)
                try store.set(try encoder.encode(newKeyVersion), forKey: currentKeyRef)
                self.currentVersion.modify {
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
        let newKey = try Self.generateKey(version: newVersion, store: store, keyPrefix: keyPrefix, keySize: keySize)
        try store.set(try encoder.encode(newVersion), forKey: currentKeyRef)
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
