//
//  LogEntries.swift
//  Logr
//

import DequeModule

/// The entries of ``LogRService/recentLogs``, newest first.
///
/// A snapshot: it never changes after you read it, and copying it is O(1) (copy-on-write). Indices are
/// zero-based `Int`s, so `logs[0]` is the newest entry and `logs.first` reads the same.
public struct LogEntries: RandomAccessCollection, Equatable, Sendable {
    private let entries: Deque<LogEntry>

    /// Creates an empty collection.
    public init() {
        entries = []
    }

    /// Creates a collection of `entries`, which must already be newest first.
    public init(_ entries: some Sequence<LogEntry>) {
        self.entries = Deque(entries)
    }

    /// Wraps the cache without copying it.
    package init(_ entries: Deque<LogEntry>) {
        self.entries = entries
    }

    public var startIndex: Int {
        entries.startIndex
    }

    public var endIndex: Int {
        entries.endIndex
    }

    public subscript(position: Int) -> LogEntry {
        entries[position]
    }
}

extension LogEntries: ExpressibleByArrayLiteral {
    /// Creates a collection of the listed entries, newest first.
    public init(arrayLiteral elements: LogEntry...) {
        self.init(elements)
    }
}
