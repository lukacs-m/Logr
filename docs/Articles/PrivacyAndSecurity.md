---
layout: default
title: Privacy and Security
nav_order: 5
parent: Logr Documentation
---

# Privacy and Security

Learn how Logr protects sensitive data through encryption and privacy-first design.

[← Back to Documentation](../index.md)

## Overview

Logr is built with privacy and security as first-class concerns, providing automatic encryption, secure key management, and privacy-aware logging practices.

## Encryption

All logs stored persistently are automatically encrypted using industry-standard cryptography.

### Encryption Algorithm

**AES-256-GCM** (default)
- Modern authenticated encryption
- Hardware-accelerated on Apple silicon
- 256-bit keys

**ChaCha20-Poly1305** (optional)
- Selectable with `try LoggerCryptoService(encryptionAlgo: .chacha)`
- The envelope records which algorithm was used; logs written before 1.3 (no algorithm field) decode as ChaCha20-Poly1305

```swift
let crypto = try LoggerCryptoService(encryptionAlgo: .chacha)
let logger = try LogR(storage: SQLiteStorage(), cryptoService: crypto)
```

### Encryption Flow

```
LogEntry (plain text)
    ↓
JSON Encoding
    ↓
AES-256-GCM / ChaCha20-Poly1305 Encryption
    ↓
Versioned Envelope
    ↓
EncryptedLogEntry
    ↓
Storage (SQLite/FileSystem)
```

### Automatic Encryption

Encryption happens automatically when using storage:

```swift
// With SQLite
let logger = try LogR(storage: SQLiteStorage())
logger.info("Sensitive data") // Automatically encrypted before storage

// With FileSystem
let logger = try LogR(storage: FileSystemStorage())
logger.info("User action") // Automatically encrypted before storage
```

### How It Works

1. **Log Created**: Plain text `LogEntry` created
2. **JSON Encoding**: Entry encoded to JSON
3. **Encryption**: Data encrypted with the configured algorithm (AES-256-GCM by default)
4. **Envelope**: Wrapped with key version for rotation support
5. **Storage**: `EncryptedLogEntry` stored in database/filesystem
6. **Decryption**: Automatic when logs are fetched

## Key Management

Encryption keys are managed securely by the `LoggerCryptoService`.

### Key Storage

- **Location**: iOS/macOS Keychain
- **Accessibility**: `.whenUnlockedThisDeviceOnly`
- **Synchronization**: Disabled (keys stay on device)
- **Size**: 256-bit (32 bytes)

### Key Generation

```swift
// Keys are generated automatically on first use
let logger = try LogR(storage: SQLiteStorage())
// On first run, a new key is generated and stored in Keychain
```

### Key Versioning

Keys are versioned to support rotation:

```swift
public struct KeyVersion: Codable, Sendable, Hashable {
    public let value: Int
}
```

Each encrypted log includes the key version used:

```swift
private struct CryptoEnvelope: Codable {
    let version: Int          // Key version
    let algorithm: CryptoAlgo // .aes256gcm or .chacha; absent in pre-1.3 envelopes → .chacha
    let data: Data            // Encrypted payload
}
```

**Benefits:**
- Rotate keys without losing access to old logs
- Decrypt logs with any historical key version
- Seamless key rotation

### Key Rotation

Rotate encryption keys manually:

```swift
// Keep a reference to the service you pass to LogR, and rotate that instance
let cryptoService = try LoggerCryptoService()
let logger = LogR(storage: try SQLiteStorage(), cryptoService: cryptoService)

// Rotate to a new key
try cryptoService.rotateKey(removeOldKeys: false)

// Rotate and remove old keys (logs encrypted with old keys become unreadable)
try cryptoService.rotateKey(removeOldKeys: true)
```

**When to Rotate:**
- Suspected key compromise
- Periodic security policy (e.g., every 90 days)
- Before regulatory audit
- After security incident

**Important:** Rotating with `removeOldKeys: true` makes old logs unreadable. Only do this if you've re-encrypted all logs or don't need historical data.

## Custom Encryption

Implement your own encryption by conforming to `LoggerCryptoServicing`. The built-in
`LoggerCryptoService` already supports AES-256-GCM (default) and ChaCha20-Poly1305, key
versioning and rotation — write a custom service only when you need a different key
source or algorithm.

```swift
import CryptoKit

struct AESCryptoService: LoggerCryptoServicing {   // the protocol is Sendable — use a struct
    private let key: SymmetricKey

    init(key: SymmetricKey) {
        // Load the key from your own store; a random key per launch cannot decrypt old logs
        self.key = key
    }

    func symmetricEncrypt(object: some Codable & Sendable) throws -> Data {
        let plaintext = try JSONEncoder().encode(object)
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        return sealedBox.combined ?? Data()
    }

    func symmetricDecrypt<T: Codable & Sendable>(encryptedData: Data) throws -> T {
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let plaintext = try AES.GCM.open(sealedBox, using: key)
        return try JSONDecoder().decode(T.self, from: plaintext)
    }
}

// Use custom encryption (`try` is for SQLiteStorage(); this LogR overload does not throw)
let customCrypto = AESCryptoService(key: myKey)
let logger = try LogR(
    storage: SQLiteStorage(),
    cryptoService: customCrypto
)
```

## Privacy-Aware Logging

### What NOT to Log

**Never log:**
- Passwords
- API keys / tokens
- Credit card numbers
- Social Security numbers
- Private keys
- Session tokens
- Biometric data
- Health information (without proper safeguards)

### What's Safe to Log

**Generally safe:**
- User IDs (not names)
- Action types
- Timestamps
- Error codes
- Feature flags
- Performance metrics
- App states

### Redacting Sensitive Data

```swift
// ❌ Bad - logs full email
logger.info("User logged in: \(userEmail)", category: .authentication)

// ✅ Good - logs user ID only
logger.info("User logged in: \(userID)", category: .authentication)

// ✅ Good - built-in redaction helper
logger.info("User logged in: \(userEmail.redactedEmail())", category: .authentication) // j***@example.com

// ✅ Good - built-in hashing helper (truncated SHA-256; .sha256 / .md5 available)
logger.info("User logged in: hash=\(userEmail.hashed())", category: .authentication)
```

Logr ships opt-in `String` helpers for the common cases: `redactedEmail(showDomain:)`,
`maskedCreditCard(visibleDigits:)`, `redactedPhone(visibleDigits:)`, `redactedIP()`,
`redactedSSN()`, `redacted(keeping:position:)`, `hashed(algorithm:)` and `fullyRedacted()`.

### Structured Logging for Privacy

```swift
// ❌ Bad - mixes sensitive and non-sensitive data
logger.info("Payment of $\(amount) from card \(cardNumber) processed")

// ✅ Good - separates concerns
logger.info("Payment processed: amount=$\(amount)", category: .payment)
logger.debug("Card ending: \(cardNumber.suffix(4))", category: .payment)

// ✅ Better - use structured data with redaction
struct PaymentLog: Codable {
    let amount: Decimal
    let lastFourDigits: String
    let timestamp: Date
    let success: Bool
}

let paymentLog = PaymentLog(
    amount: amount,
    lastFourDigits: String(cardNumber.suffix(4)),
    timestamp: Date(),
    success: true
)

logger.info("Payment processed: \(paymentLog)", category: .payment)
```

### Logr's Approach

Logr passes the message to `os.Logger` through string interpolation without a `privacy:`
argument, so the unified logging system applies its default: the interpolated message is
rendered as `<private>` in Console.app for release builds unless private-data logging is
enabled. Nothing in Logr redacts content itself — use the helpers above before logging.
The in-memory `recentLogs` cache and `LogViewer` show plain text, and **persistent storage
is always encrypted**. Set `LogrConfiguration(mirrorToOSLog: false)` to keep logs out of
OSLog entirely.

```swift
logger.info("Sensitive data: \(data)")
// OSLog: "Sensitive data: <private>" (in Console.app)
// Storage: Fully encrypted including "Sensitive data: <actual data>"
```

## Privacy Scanning with AI (iOS 26+)

Use AI to detect privacy issues in your logs:

```swift
if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *) {
    Task { @MainActor in
        let result = try await logger.scanForPrivacyIssues()

        if !result.isEmpty {
            print("⚠️ \(result.summary)")

            for warning in result.warnings {
                print("  - [\(warning.severity)] \(warning.exposureType) at \(warning.file):\(warning.line)")
                print("    Recommendation: \(warning.recommendation)")
            }
        }
    }
}
```

See [AI Analysis](./AIAnalysis.md) for details.

## Compliance

### GDPR Compliance

Logr supports GDPR requirements:

**Right to Erasure:**
```swift
// Delete all user logs
try await logger.clearLogs()
```

**Data Portability:**
```swift
// Export logs in standard format
let jsonData = try await logger.exportLogs(format: .json)
// Provide to user
```

**Privacy by Design:**
- Automatic encryption
- Minimal data retention (configurable)
- No external transmission (on-device only)


### SOC 2 Compliance

Logr supports audit requirements:

**Audit Trail:**
```swift
// All logs are timestamped and immutable
let logs = logger.recentLogs.sorted { $0.timestamp < $1.timestamp }   // recentLogs is newest first
```

**Access Control:**
```swift
// Logs are encrypted at rest
// Keys are in device Keychain only
```

**Data Retention:**
```swift
// Configurable retention policies
let config = LogrConfiguration(
    maxLogAge: 90 * 24 * 60 * 60, // 90 days
    cleanupInterval: 24 * 60 * 60 // Daily cleanup
)
```

## Security Best Practices

### 1. Use Encrypted Storage

Always use storage with encryption in production:

```swift
// ✅ Production
let logger = try LogR(storage: SQLiteStorage())

// ❌ Only for development
let logger = try LogR()
```

### 2. Configure Appropriate Retention

Don't keep logs longer than needed:

```swift
let config = LogrConfiguration(
    maxLogAge: 7 * 24 * 60 * 60, // 7 days
    maxLogEntries: 5_000
)
```

### 3. Disable Debug Logs in Production

```swift
#if DEBUG
let levels: Set<LogLevel> = Set(LogLevel.allCases)
#else
let levels: Set<LogLevel> = [.info, .warning, .error, .fault]
#endif

let config = LogrConfiguration(enabledLevels: levels)
```

### 4. Regular Cleanup

Ensure cleanup runs regularly:

```swift
let config = LogrConfiguration(
    cleanupInterval: 60 * 60 // Every hour
)
```

### 5. Sanitize User Input

Never log unsanitized user input:

```swift
// ❌ Bad - potential injection
logger.info("Search query: \(userInput)")

// ✅ Good - sanitized
let sanitized = userInput
    .replacingOccurrences(of: "\n", with: " ")
    .prefix(100)
logger.info("Search query: \(sanitized)")
```

### 6. Audit Logging Regularly

Review logs for privacy issues:

```swift
#if DEBUG
@MainActor
func auditLogs() async {
    if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *) {
        let result = try? await logger.scanForPrivacyIssues()

        if let result, result.criticalCount > 0 || result.highCount > 0 {
            print("⚠️ Privacy audit failed: \(result.summary)")
            for warning in result.warnings {
                print("  - [\(warning.severity)] \(warning.exposureType): \(warning.explanation)")
            }
        }
    }
}
#endif
```

### 7. Secure Key Storage

Never extract or export encryption keys:

```swift
// ❌ Bad - exposes key
let key = cryptoService.getCurrentKey() // Don't do this

// ✅ Good - keys stay in crypto service
let logger = try LogR(storage: SQLiteStorage()) // Keys managed internally
```

### 8. Use Categories Wisely

Categorize logs to identify sensitive operations:

```swift
// Helps identify logs that may contain sensitive data
logger.info("Operation started", category: .authentication)
logger.info("Card processed", category: .payment)
logger.info("Health data accessed", category: .custom("healthcare"))
```

## Threat Model

### What Logr Protects Against

✅ **Unauthorized Access to Storage**
- All logs encrypted at rest
- Keys stored in Keychain

✅ **Data Exfiltration**
- Encrypted storage prevents reading logs
- Keys never leave device

✅ **Accidental Exposure**
- Automatic encryption
- No plain-text storage

✅ **Device Theft**
- Keychain tied to device
- Requires device unlock for key access

### What Logr Doesn't Protect Against

❌ **Logging Sensitive Data**
- Logr encrypts storage, but can't prevent you from logging sensitive data
- Use privacy-aware logging practices

❌ **Memory Dumps**
- In-memory cache (`recentLogs`) contains plain-text logs
- Use `maxLogEntries` to limit exposure

❌ **Compromised Device**
- If device is fully compromised (jailbroken, malware), encryption keys may be accessible

❌ **Screen Recording**
- If using `LogViewer`, logs visible on screen can be captured

## Security Incident Response

If you suspect a security incident:

### 1. Assess the Breach

```swift
// Rotate the keys of the crypto service you passed to LogR
try cryptoService.rotateKey(removeOldKeys: false)
```

### 2. Clear Sensitive Logs

```swift
// Clear all existing logs
try await logger.clearLogs()

// Or selectively clear
let logsToKeep = logger.recentLogs.filter { entry in
    // Keep only system logs
    entry.category == .system || entry.category == .lifecycle
}

try await logger.clearLogs()
for log in logsToKeep {
    // Re-log safe entries
}
```

### 3. Update Configuration

```swift
// Reduce retention after incident
let config = LogrConfiguration(
    maxLogAge: 24 * 60 * 60, // Reduce to 24 hours
    maxLogEntries: 1_000     // Reduce to 1,000 entries
)
```

### 4. Audit for Privacy Issues

```swift
if #available(iOS 26.0, *) {
    let result = try await logger.scanForPrivacyIssues()

    // Review all warnings
    for warning in result.warnings {
        // Document and address each issue
    }
}
```

## Summary

Logr provides:

✅ **Strong Encryption** - AES-256-GCM (default) or ChaCha20-Poly1305, 256-bit keys
✅ **Secure Key Management** - Keychain storage, versioned keys
✅ **Privacy by Design** - Automatic encryption, minimal retention
✅ **Compliance Ready** - Supports GDPR, SOC 2
✅ **AI-Powered Auditing** - Detect privacy issues automatically (iOS 26+)

Follow privacy-aware logging practices and use Logr's encryption features to protect your users' data.

## Related Documentation

- [AI Analysis](./AIAnalysis.md) - Privacy scanning with AI
- [Storage and Persistence](./StorageAndPersistence.md) - Storage options
- [Architecture](./Architecture.md) - Security architecture
