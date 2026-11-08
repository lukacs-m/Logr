//
//  LogIssueDigest.swift
//  Logr
//

import CryptoKit
import Foundation

/// The warning, error and fault entries of the recent logs, grouped by call site and message template.
///
/// Built by ``LogRService/issueDigest()`` on every platform, without a language model. Counts are exact over the
/// entries in ``LogRService/recentLogs`` at the time of the call.
public struct LogIssueDigest: Sendable, Hashable {
    /// Sorted by level (most severe first), then ``LogIssueGroup/count`` (descending), then ``LogIssueGroup/id``.
    public let groups: [LogIssueGroup]
    /// The number of ``LogLevel/error`` entries.
    public let totalErrors: Int
    /// The number of ``LogLevel/warning`` entries.
    public let totalWarnings: Int
    /// The number of ``LogLevel/fault`` entries.
    public let totalFaults: Int

    public init(groups: [LogIssueGroup], totalErrors: Int, totalWarnings: Int, totalFaults: Int) {
        self.groups = groups
        self.totalErrors = totalErrors
        self.totalWarnings = totalWarnings
        self.totalFaults = totalFaults
    }

    public var isEmpty: Bool {
        groups.isEmpty
    }

    public static let empty = LogIssueDigest(groups: [], totalErrors: 0, totalWarnings: 0, totalFaults: 0)
}

/// Entries logged at one call site whose messages differ only in their values.
public struct LogIssueGroup: Sendable, Identifiable, Hashable {
    /// A hash of the file, line and template: the same in every run and on every device.
    public let id: String
    /// The most severe level among the group's entries.
    public let level: LogLevel
    /// The category of the newest entry.
    public let category: LogCategory
    /// The `#fileID` of the call site.
    public let file: String
    public let line: Int
    /// The message with numbers, UUIDs, hex values and quoted strings replaced by `<number>`, `<uuid>`, `<hex>`
    /// and `<string>`, and private values by `<private>`.
    public let template: String
    /// The number of entries in the group.
    public let count: Int
    public let firstSeen: Date
    public let lastSeen: Date
    /// The newest entry's message, private values replaced by `<private>`, cut to 300 characters.
    public let sampleMessage: String

    public init(id: String, level: LogLevel, category: LogCategory, file: String, line: Int, template: String,
                count: Int, firstSeen: Date, lastSeen: Date, sampleMessage: String) {
        self.id = id
        self.level = level
        self.category = category
        self.file = file
        self.line = line
        self.template = template
        self.count = count
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.sampleMessage = sampleMessage
    }
}

// MARK: - Building

extension LogIssueDigest {
    @concurrent
    static func make(from entries: LogEntries) async -> LogIssueDigest {
        var groups: [String: LogIssueGroup] = [:]
        var totals: [LogLevel: Int] = [:]
        // Newest first, so the first entry of a group is its newest.
        for entry in entries where entry.level.priority >= LogLevel.warning.priority {
            totals[entry.level, default: 0] += 1
            let message = entry.redactingPrivateValues().message
            let template = template(for: message)
            let key = "\(entry.file)\u{0}\(entry.line)\u{0}\(template)"
            guard let group = groups[key] else {
                let sample = message.count > 300 ? message.prefix(299) + "…" : message
                groups[key] = LogIssueGroup(id: id(for: key), level: entry.level, category: entry.category,
                                            file: entry.file, line: entry.line, template: template, count: 1,
                                            firstSeen: entry.timestamp, lastSeen: entry.timestamp,
                                            sampleMessage: String(sample))
                continue
            }
            groups[key] = LogIssueGroup(id: group.id,
                                        level: entry.level.priority > group.level.priority ? entry.level : group
                                            .level,
                                        category: group.category, file: group.file, line: group.line,
                                        template: template, count: group.count + 1,
                                        firstSeen: min(group.firstSeen, entry.timestamp),
                                        lastSeen: max(group.lastSeen, entry.timestamp),
                                        sampleMessage: group.sampleMessage)
        }
        let sorted = groups.values.sorted {
            ($1.level.priority, $1.count, $0.id) < ($0.level.priority, $0.count, $1.id)
        }
        return LogIssueDigest(groups: sorted, totalErrors: totals[.error, default: 0],
                              totalWarnings: totals[.warning, default: 0], totalFaults: totals[.fault, default: 0])
    }

    /// Replaces the values in `message` with placeholders, so messages from one call site that differ only in
    /// their values share a template.
    static func template(for message: String) -> String {
        replacements.reduce(message) { text, replacement in
            replacement.regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                                       withTemplate: replacement.placeholder)
        }
    }

    /// In order: hashed placeholders hold hex, quoted strings and UUIDs hold numbers.
    private static let replacements: [(regex: NSRegularExpression, placeholder: String)] = [
        ("<private:[0-9a-f]{8}>", "<private>"),
        (#""[^"]*""#, "<string>"),
        ("(?<![A-Za-z0-9])'[^'\\s][^']*'(?![A-Za-z0-9])", "<string>"),
        ("[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}", "<uuid>"),
        ("\\b0x[0-9A-Fa-f]+\\b", "<hex>"),
        ("\\b(?=[0-9A-Fa-f]*[0-9])(?=[0-9A-Fa-f]*[A-Fa-f])[0-9A-Fa-f]{6,}\\b", "<hex>"),
        ("(?<![A-Za-z0-9_.])-?[0-9]+(?:\\.[0-9]+)*(?![A-Za-z0-9_])", "<number>")
    ].map { pattern, placeholder in
        // Fixed patterns: a typo fails every digest test, never a user's input.
        (try! NSRegularExpression(pattern: pattern), placeholder)
    }

    private static func id(for key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
