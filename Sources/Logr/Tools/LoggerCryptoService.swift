//  
//  LoggerCryptoService.swift
//  Logr
//
//  Created by martin on 02/11/2025.
//

import Foundation
import CryptoKit
@preconcurrency import KeychainAccess

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

public protocol LoggerCryptoServicing {
    func symmetricEncrypt(object: some Codable & Sendable) throws -> Data
    func symmetricDecrypt<T: Codable & Sendable>(encryptedData: Data) throws -> T
}

// MARK: - Actor: LoggerCryptoService
public final class LoggerCryptoService: LoggerCryptoServicing {
    private let store: KeychainStore
    private let currentKeyRef = "logger_current_key_version"
    private let keyPrefix = "logger_sym_key_v"
    private let keySize = 32  // 256 bits
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private(set) var currentVersion: KeyVersion
    private var cacheKeys: [KeyVersion: SymmetricKey] = [:]
    
    // MARK: - Init
    public init(store: KeychainStore = KeychainAccessStore(service: "com.logr.KeychainStore")) {
        self.store = store
        if let versionData = try? store.data(forKey: currentKeyRef),
           let version = try? decoder.decode(KeyVersion.self, from: versionData) {
            self.currentVersion = version
        } else {
            do {
                let newKeyVersion = KeyVersion.default
                let key = try Self.generateKey(version: newKeyVersion, store: store, keyPrefix: keyPrefix, keySize: keySize)
                try store.set(try encoder.encode(newKeyVersion), forKey: currentKeyRef)
                self.currentVersion = newKeyVersion
                cacheKeys[newKeyVersion] = key
            } catch {
                fatalError("Failed to generate initial key with error \(error.localizedDescription)")
            }
        }
    }
    
   public func symmetricEncrypt(object: some Codable) throws -> Data {
        guard let symmetricKey = try loadKey(version: currentVersion) else {
            throw LoggerCryptoError.keyNotFound(version: currentVersion.value)
        }
        let data = try JSONEncoder().encode(object)
        return try symmetricKey.encrypt(data)
    }
    
    public func symmetricDecrypt<T: Codable & Sendable>(encryptedData: Data) throws -> T {
        guard let symmetricKey = try loadKey(version: currentVersion) else {
            throw LoggerCryptoError.keyNotFound(version: currentVersion.value)
        }
        let data = try symmetricKey.decrypt(encryptedData)
        return try JSONDecoder().decode(T.self, from: data)
    }


//    // MARK: - Encrypt
//    public func encrypt(_ plaintext: Data, associatedData: Data? = nil) async throws -> Data {
//        guard let key = try loadKey(version: currentVersion) else {
//            throw LoggerCryptoError.keyNotFound(version: currentVersion.value)
//        }
//
//        let sealedBox: AES.GCM.SealedBox
//        do {
//            if let ad = associatedData {
//                sealedBox = try AES.GCM.seal(plaintext, using: key, authenticating: ad)
//            } else {
//                sealedBox = try AES.GCM.seal(plaintext, using: key)
//            }
//        } catch {
//            throw LoggerCryptoError.encryptionFailed
//        }
//
//        guard let combined = sealedBox.combined else {
//            throw LoggerCryptoError.invalidEnvelope
//        }
//
//        var envelope = Data()
//        envelope.append(try JSONEncoder().encode(currentVersion))
//        envelope.append(combined)
//        return envelope
//    }
//
//    // MARK: - Decrypt
//    public func decrypt(_ envelope: Data, associatedData: Data? = nil) async throws -> Data {
//        guard envelope.count > MemoryLayout<Int>.size else {
//            throw LoggerCryptoError.invalidEnvelope
//        }
//
//        // Decode version prefix
//        let decoder = JSONDecoder()
//        // Try to decode KeyVersion from the front
//        // (simplified assumption: version encoding fixed-length JSON)
//        guard let versionRange = envelope.firstRange(of: "}".data(using: .utf8) ?? Data()) else {
//            throw LoggerCryptoError.invalidEnvelope
//        }
//        let versionData = envelope.prefix(upTo: versionRange.upperBound)
//        let cipherData = envelope.suffix(from: versionRange.upperBound)
//        let version = try decoder.decode(KeyVersion.self, from: versionData)
//
//        guard let key = try loadKey(version: version) else {
//            throw LoggerCryptoError.keyNotFound(version: version.value)
//        }
//
//        let sealedBox = try AES.GCM.SealedBox(combined: cipherData)
//        do {
//            if let ad = associatedData {
//                return try AES.GCM.open(sealedBox, using: key, authenticating: ad)
//            } else {
//                return try AES.GCM.open(sealedBox, using: key)
//            }
//        } catch {
//            throw LoggerCryptoError.decryptionFailed
//        }
//    }

    // MARK: - Rotation
    public func rotateKey(removeOldKeys: Bool = false) throws {
        let newVersion = KeyVersion(currentVersion.value + 1)
        let newKey = try Self.generateKey(version: newVersion, store: store, keyPrefix: keyPrefix, keySize: keySize)
        try store.set(try encoder.encode(newVersion), forKey: currentKeyRef)
        if removeOldKeys {
            try? store.remove(forKey: keyName(for: currentVersion))
        }
        currentVersion = newVersion
        cacheKeys[newVersion] = newKey
    }
}

// MARK: - Private Helpers

private extension LoggerCryptoService {
    
    func keyName(for version: KeyVersion) -> String {
        "\(keyPrefix)\(version.value)"
    }
    
    func loadKey(version: KeyVersion) throws -> SymmetricKey? {
        if let key =  cacheKeys[version] {
            return key
        }
        guard let keyData = try store.data(forKey: keyName(for: version)) else {
            return nil
        }
        let symmetricKey = SymmetricKey(data: keyData)
        cacheKeys[version] = symmetricKey
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

// MARK: - Data helpers (Swift 6.2 utility)
extension Data {
    static func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }
}

//
//public extension Data {
//    static func random(byteCount: Int = 32) throws -> Data {
//        var data = Data(count: byteCount)
//        _ = try data.withUnsafeMutableBytes { byte in
//            guard let baseAddress = byte.baseAddress else {
//                throw AuthError.generic(.failedToRandomizeData)
//            }
//            return SecRandomCopyBytes(kSecRandomDefault, byteCount, baseAddress)
//        }
//        return data
//    }
//
//    var hexString: String {
//        map { String(format: "%02hhx", $0) }.joined()
//    }
//}


//
//
//import CommonUtilities
//import CryptoKit
//import Foundation
//import Models
//@preconcurrency import ProtonCoreKeymaker
//
//public protocol KeysProvider: Sendable {
//    func getSymmetricKey() throws -> SymmetricKey
//
//    func get(keyId: String) throws -> Data
//    func set(_ keyData: Data, for keyId: String) throws
//    func clear(keyId: String, isSynced: Bool) throws
//}
//
//public extension KeysProvider {
//    func clear(keyId: String, isSynced: Bool = true) throws {
//        try clear(keyId: keyId, isSynced: isSynced)
//    }
//}
//
//public protocol MainKeyProvider: Sendable, AnyObject {
//    var mainKey: MainKey? { get }
//}
//
//extension Keymaker: @unchecked @retroactive Sendable, MainKeyProvider {
//    override public convenience init() {
//        let keychain = CoreKeychain()
//        let locker = Autolocker(lockTimeProvider: keychain)
//        self.init(autolocker: locker, keychain: keychain)
//    }
//}
//
//final class CoreKeychain: Keychain, @unchecked Sendable {
//    init() {
//        super.init(service: "me.proton.authenticator", accessGroup: AppConstants.keychainGroup)
//    }
//}
//
//extension CoreKeychain: SettingsProvider {
//    private static let LockTimeKey = "AuthAccount.LockTimeKey"
//
//    var lockTime: AutolockTimeout {
//        get {
//            guard let string = try? stringOrError(forKey: Self.LockTimeKey), let intValue = Int(string) else {
//                return .never
//            }
//            return AutolockTimeout(rawValue: intValue)
//        }
//        set {
//            do {
//                try setOrError(String(newValue.rawValue), forKey: Self.LockTimeKey)
//            } catch {
//                print("Failed to set lockTime with error: \(error)")
//            }
//        }
//    }
//}
//
//public final class KeysManager: KeysProvider {
//    private let keychain: any KeychainServicing
//    private let keyMaker: any MainKeyProvider
//    private let keychainKey = "SymmetricKey"
//
//    public init(keychain: any KeychainServicing,
//                keyMaker: any MainKeyProvider = Keymaker()) {
//        self.keychain = keychain
//        self.keyMaker = keyMaker
//    }
//
//    public func getSymmetricKey() throws -> SymmetricKey {
//        guard let mainKey = keyMaker.mainKey else {
//            throw AuthError.generic(.mainKeyNotFound)
//        }
//
//        // At this point either migration is done or no key is generated (first installation)
//        // so we proceed as normal (get if exist and random if not)
//        if let lockedSymmetricKeyData: Data = try? keychain.get(keyId: keychainKey, isSynced: true) {
//            try migrationSymmetricKeyToUnsync(lockedSymmetricKeyData)
//            return try unlockSymmetricKey(mainKey: mainKey, lockedSymmetricKeyData)
//        } else if let lockedSymmetricKeyData: Data = try? keychain.get(keyId: keychainKey, isSynced: false) {
//            return try unlockSymmetricKey(mainKey: mainKey, lockedSymmetricKeyData)
//        } else {
//            return try buildSymmetricKey(mainKey: mainKey)
//        }
//    }
//
//    public func get(keyId: String) throws -> Data {
//        let keyData: Data = try keychain.get(keyId: keyId, isSynced: true)
//        return keyData
//    }
//
//    public func set(_ keyData: Data, for keyId: String) throws {
//        try keychain.set(keyData, for: keyId, shouldSync: true)
//    }
//
//    public func clear(keyId: String, isSynced: Bool) throws {
//        try keychain.delete(keyId: keyId, isSynced: isSynced)
//    }
//}
//
//private extension KeysManager {
//    func migrationSymmetricKeyToUnsync(_ lockedSymmetricKeyData: Data) throws {
//        try keychain.delete(keyId: keychainKey, isSynced: true)
//        try keychain.set(lockedSymmetricKeyData, for: keychainKey, shouldSync: false)
//    }
//
//    func buildSymmetricKey(mainKey: MainKey) throws -> SymmetricKey {
//        let randomData = try Data.random()
//        let lockedData = try Locked<Data>(clearValue: randomData, with: mainKey)
//        try keychain.set(lockedData.encryptedValue, for: keychainKey, shouldSync: false)
//        return .init(data: randomData)
//    }
//
//    func unlockSymmetricKey(mainKey: MainKey, _ lockedSymmetricKeyData: Data) throws -> SymmetricKey {
//        let lockedData = Locked<Data>(encryptedValue: lockedSymmetricKeyData)
//        var unlockedData: Data
//        do {
//            unlockedData = try lockedData.unlock(with: mainKey)
//        } catch {
//            return try buildSymmetricKey(mainKey: mainKey)
//        }
//        return .init(data: unlockedData)
//    }
//}

 extension SymmetricKey {
//    /// Encrypt a string into base64 format
//    func encrypt(_ clearText: String) throws -> String {
//        guard let data = clearText.data(using: .utf8) else {
//            throw AuthError.symmetricCrypto(.failedToConvertUtf8ToData(clearText))
//        }
//        let cypherData = try ChaChaPoly.seal(data, using: self).combined
//        return cypherData.base64EncodedString()
//    }

    func encrypt(_ clearData: Data) throws -> Data {
        try ChaChaPoly.seal(clearData, using: self).combined
    }

//    /// Decrypt an encrypted base64 string
//    func decrypt(_ cypherText: String) throws -> String {
//        guard let data = Data(base64Encoded: cypherText) else {
//            throw AuthError.symmetricCrypto(.failedToBase64Decode(cypherText))
//        }
//        let sealedBox = try ChaChaPoly.SealedBox(combined: data)
//        let decryptedData = try ChaChaPoly.open(sealedBox, using: self)
//        // swiftlint:disable:next optional_data_string_conversion
//        return String(decoding: decryptedData, as: UTF8.self)
//    }

    func decrypt(_ cypherData: Data) throws -> Data {
        let sealedBox = try ChaChaPoly.SealedBox(combined: cypherData)
        return try ChaChaPoly.open(sealedBox, using: self)
    }
}
