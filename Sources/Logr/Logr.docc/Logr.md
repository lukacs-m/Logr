# ``Logr``

Persistent, encrypted logging for Apple platforms, built on OSLog.

## Overview

Create one ``LogR`` at the app root and log through ``LogRService``. Logging is `nonisolated`:
call it from any actor or thread with no `await`. Every entry goes to an in-memory cache and to
OSLog; when a ``LogRPersistence`` is supplied, entries are also encrypted through
``LoggerCryptoServicing`` and persisted on a background actor. ``LogR`` documents the pipeline,
the isolation model and the lifecycle. Compiled usage examples live in the package README.

The `LogrUI` module adds a SwiftUI viewer, statistics views and a mock service for previews.

## Topics

### Essentials

- ``LogR``
- ``LogRService``
- ``LogrConfiguration``
- ``LogVerbosity``

### Entries

- ``LogEntry``
- ``LogLevel``
- ``LogCategory``
- ``LogMetadataValue``

### Storage

- ``LogRPersistence``
- ``SQLiteStorage``
- ``FileSystemStorage``
- ``EncryptedLogEntry``

### Encryption

- ``LoggerCryptoServicing``
- ``LoggerCryptoService``
- ``KeychainStore``
- ``KeychainAccessStore``
- ``KeyVersion``
- ``LoggerCryptoError``

### Redaction

- ``Swift/String/redactedEmail(showDomain:)``
- ``Swift/String/maskedCreditCard(visibleDigits:)``
- ``Swift/String/redactedPhone(visibleDigits:)``
- ``Swift/String/redactedIP()``
- ``Swift/String/redactedSSN()``
- ``Swift/String/redacted(keeping:position:)``
- ``Swift/String/hashed(algorithm:)``
- ``Swift/String/fullyRedacted()``
- ``RedactionPosition``
- ``HashAlgorithm``

### Export and statistics

- ``ExportFormat``
- ``LogStatistics``
- ``LogTimeSeriesPoint``
- ``ShareItem``
- ``LogExportError``

### AI analysis

- ``LogAIAnalyzer``
- ``AIAnalyzer``
- ``AnalyzerConfiguration``
- ``PrivacyAnalysisResult``
- ``PrivacyWarning``
- ``LogIssueSummary``
- ``LogIssue``
- ``LogSeverity``
- ``AnalysisProgress``
- ``AIAnalyzerError``

### Errors

- ``LogRErrors``
