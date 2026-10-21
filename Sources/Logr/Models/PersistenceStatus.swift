//
//  PersistenceStatus.swift
//  Logr
//

/// Whether ``LogR`` is writing entries to its storage. Read it from ``LogRService/persistenceStatus``.
public enum PersistenceStatus: Sendable, Equatable {
    /// No storage is configured: entries live in memory only.
    case disabled

    /// The logger was just created and is opening its storage and reading its key in the background. Entries wait
    /// in memory until the first attempt ends, with ``active``, ``waitingForProtectedData`` or ``failed(_:)``.
    case opening

    /// Entries are written to storage.
    case active

    /// The encryption key cannot be read until the device is unlocked for the first time after a restart (a
    /// storage that fails to open meanwhile is put down to the same cause). Entries wait in memory, up to the
    /// writer's backpressure cap, and are written once the key can be read.
    case waitingForProtectedData

    /// Storage could not be opened or written, or entries could not be encrypted, for the given reason.
    ///
    /// While storage cannot be opened, entries wait in memory and opening is retried every 30 seconds. Entries
    /// that cannot be encrypted or written are dropped and counted in ``LogRService/droppedLogCount``; the next
    /// entry written returns the status to ``active``.
    case failed(String)
}
