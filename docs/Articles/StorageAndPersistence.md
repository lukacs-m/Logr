---
layout: default
title: Storage and Persistence
nav_order: 4
parent: Logr Documentation
---

# Storage and Persistence

Learn about Logr's storage options and how to implement custom storage backends.

[← Back to Documentation](../index.md)

## Overview

Logr provides flexible storage options for persisting logs. All stored logs are automatically encrypted using ChaCha20-Poly1305 with keys stored securely in the Keychain.

## Storage Options

### No Storage (OSLog Only)

Use Logr without persistent storage:

```swift
let logger = try LogR()
```

**When to use:**
- Quick prototyping
- When you only need system-level logging
- When disk space is extremely limited

**Limitations:**
- Logs cleared on app restart
- No log export functionality
- No historical analysis

### FileSystem Storage

Simple JSON-based file storage:

```swift
let logger = try LogR(storage: FileSystemStorage())
```

**Features:**
- One JSON file per log entry
- Human-readable (when decrypted)
- Easy to backup
- Simple implementation

**Best for:**
- Apps with moderate log volumes (<1,000 logs/day)
- Development and debugging
- When you need to inspect raw files

**File Structure:**
```
Documents/
└── com.logr.storage/
    ├── log_uuid1.json
    ├── log_uuid2.json
    └── log_uuid3.json
```

### SQLite Storage (Recommended)

High-performance SQLite database:

```swift
let logger = try LogR(storage: SQLiteStorage())
```

**Features:**
- Optimized for mobile devices
- Efficient querying
- Automatic indexing
- ACID transactions

**Best for:**
- Production apps
- High log volumes (>1,000 logs/day)
- Apps requiring advanced querying
- Long-term log storage

**Schema:**
```sql
CREATE TABLE encrypted_logs (
    id TEXT PRIMARY KEY,
    timestamp REAL NOT NULL,
    data BLOB NOT NULL
);

CREATE INDEX idx_timestamp ON encrypted_logs(timestamp);
```

## Using Storage

### Basic Setup

```swift
import Logr

// SQLite (recommended)
let logger = try LogR(storage: SQLiteStorage())

// FileSystem
let logger = try LogR(storage: FileSystemStorage())

// No storage
let logger = try LogR()
```

### Custom Storage Location

Specify a custom directory for storage:

```swift
// Custom documents subdirectory
let documentsURL = FileManager.default
    .urls(for: .documentDirectory, in: .userDomainMask)[0]
let customURL = documentsURL.appendingPathComponent("MyLogs")

let storage = FileSystemStorage(directoryURL: customURL)
let logger = try LogR(storage: storage)
```

### App Group Storage

Share logs across app extensions:

```swift
let groupURL = FileManager.default
    .containerURL(forSecurityApplicationGroupIdentifier: "group.com.myapp")!
let storage = SQLiteStorage(databaseURL: groupURL.appendingPathComponent("logs.db"))

let logger = try LogR(storage: storage)
```

## Custom Storage Implementation

Implement the `LogRPersistence` protocol for custom storage:

```swift
import Logr
import Foundation

class CloudStorage: LogRPersistence {
    private let apiClient: APIClient
    private var cache: [EncryptedLogEntry] = []

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func store(_ entry: EncryptedLogEntry) async throws {
        // Upload to cloud service
        try await apiClient.upload(entry)

        // Also cache locally
        cache.append(entry)

        // Trim cache if needed
        if cache.count > 1000 {
            cache.removeFirst(cache.count - 1000)
        }
    }

    func fetchEntries() async throws -> [EncryptedLogEntry] {
        // Return from local cache for quick access
        // Or fetch from cloud if needed
        return cache
    }

    func deleteEntries(olderThan date: Date) async throws {
        // Delete from cloud
        try await apiClient.deleteOldEntries(before: date)

        // Update cache
        cache.removeAll { $0.timestamp < date }
    }

    func deleteEntries(keepingLatest count: Int) async throws {
        guard cache.count > count else { return }

        let toDelete = cache.count - count
        let entriesToDelete = Array(cache.prefix(toDelete))

        // Delete from cloud
        for entry in entriesToDelete {
            try await apiClient.delete(id: entry.id)
        }

        // Update cache
        cache.removeFirst(toDelete)
    }

    func clear() async throws {
        try await apiClient.deleteAllLogs()
        cache.removeAll()
    }

    func count() async throws -> Int {
        return cache.count
    }
}

// Use it
let cloudStorage = CloudStorage(apiClient: myAPIClient)
let logger = try LogR(storage: cloudStorage)
```

### Core Data Storage Example

```swift
import Logr
import CoreData

class CoreDataStorage: LogRPersistence {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func store(_ entry: EncryptedLogEntry) async throws {
        try await context.perform {
            let logObject = EncryptedLog(context: self.context)
            logObject.id = entry.id
            logObject.timestamp = entry.timestamp
            logObject.data = entry.data

            try self.context.save()
        }
    }

    func fetchEntries() async throws -> [EncryptedLogEntry] {
        try await context.perform {
            let request = EncryptedLog.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]

            let results = try self.context.fetch(request)

            return results.map { logObject in
                EncryptedLogEntry(
                    id: logObject.id!,
                    timestamp: logObject.timestamp!,
                    data: logObject.data!
                )
            }
        }
    }

    func deleteEntries(olderThan date: Date) async throws {
        try await context.perform {
            let request = EncryptedLog.fetchRequest()
            request.predicate = NSPredicate(format: "timestamp < %@", date as NSDate)

            let results = try self.context.fetch(request)
            results.forEach { self.context.delete($0) }

            try self.context.save()
        }
    }

    // Implement other methods...
}
```

## Storage Best Practices

### 1. Choose the Right Storage

```swift
// For production apps with high volumes
let logger = try LogR(storage: SQLiteStorage())

// For simple apps or prototyping
let logger = try LogR(storage: FileSystemStorage())

// For development without persistence needs
let logger = try LogR()
```

### 2. Configure Retention Appropriately

```swift
let config = LogrConfiguration(
    maxLogEntries: 5_000,        // Balance memory usage
    maxLogAge: 7 * 24 * 60 * 60, // Balance disk usage
    cleanupInterval: 60 * 60     // Regular cleanup
)

let logger = try LogR(
    storage: SQLiteStorage(),
    configuration: config
)
```

### 3. Handle Storage Errors

```swift
class MyStorage: LogRPersistence {
    func store(_ entry: EncryptedLogEntry) async throws {
        do {
            try await performStorage(entry)
        } catch {
            // Log error (to OSLog, not Logr to avoid recursion)
            print("Storage error: \(error)")

            // Optionally retry
            try await performStorage(entry)
        }
    }
}
```

### 4. Optimize Cleanup

```swift
func deleteEntries(keepingLatest count: Int) async throws {
    // Get total count efficiently
    let total = try await fastCount()

    guard total > count else { return }

    // Calculate cutoff timestamp for batch delete
    let toDelete = total - count
    let entries = try await fetchEntries(limit: toDelete, sortedBy: .timestamp)

    guard let cutoffDate = entries.last?.timestamp else { return }

    // Batch delete all entries older than cutoff
    try await deleteEntries(olderThan: cutoffDate)
}
```

## Encryption

All storage implementations automatically encrypt logs using the crypto service.

### How It Works

1. **Log Entry Created**: `LogEntry` with plain text message
2. **Encryption**: Entry encoded to JSON and encrypted with ChaCha20-Poly1305
3. **Storage**: `EncryptedLogEntry` with encrypted Data stored
4. **Retrieval**: Encrypted data fetched from storage
5. **Decryption**: Data decrypted and decoded back to `LogEntry`

### Key Management

- Keys stored in Keychain (`.whenUnlockedThisDeviceOnly`)
- Automatic key generation on first use
- Key versioning for rotation support
- Keys never leave the device

### Custom Crypto

Provide your own encryption:

```swift
class MyCustomCrypto: LoggerCryptoServicing {
    func symmetricEncrypt<T: Codable>(object: T) throws -> Data {
        // Your encryption
    }

    func symmetricDecrypt<T: Codable>(encryptedData: Data) throws -> T {
        // Your decryption
    }
}

let logger = LogR(
    storage: SQLiteStorage(),
    cryptoService: MyCustomCrypto()
)
```

## Performance Tips

### SQLite Optimization

```swift
// Use transactions for batch operations
func storeBatch(_ entries: [EncryptedLogEntry]) async throws {
    try await database.write { db in
        for entry in entries {
            try entry.insert(db)
        }
    }
}

// Create indexes for common queries
CREATE INDEX idx_timestamp ON encrypted_logs(timestamp DESC);

// Use LIMIT for large result sets
SELECT * FROM encrypted_logs ORDER BY timestamp DESC LIMIT 1000;
```

### FileSystem Optimization

```swift
// Limit directory scans
private var cachedFileList: [String] = []
private var lastScan: Date?

func fetchEntries() async throws -> [EncryptedLogEntry] {
    // Rescan only if needed
    let now = Date()
    if let lastScan, now.timeIntervalSince(lastScan) < 60 {
        // Use cached list
    } else {
        // Rescan directory
        cachedFileList = try FileManager.default
            .contentsOfDirectory(atPath: directoryURL.path)
        lastScan = now
    }

    // Load files
}
```

## Summary

Logr provides flexible storage options:

- **FileSystem**: Simple, inspectable, good for moderate volumes
- **SQLite**: Fast, scalable, recommended for production
- **Custom**: Implement `LogRPersistence` for any backend

All storage is automatically encrypted with ChaCha20-Poly1305 and keys stored in Keychain for maximum security.

## Related Documentation

- [Architecture](./Architecture.md) - How storage fits in the system
- [Privacy and Security](./PrivacyAndSecurity.md) - Encryption details
- [Getting Started](./GettingStarted.md) - Basic setup
