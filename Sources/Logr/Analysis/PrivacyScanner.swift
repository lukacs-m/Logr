//
//  PrivacyScanner.swift
//  Logr
//

import Foundation

/// Runs ``PrivacyDetector``s over log entries and groups what they find by call site.
enum PrivacyScanner {
    @concurrent
    static func scan(_ entries: LogEntries, detectors: [PrivacyDetector]) async -> PrivacyAnalysisResult {
        // Contiguous chunks scanned in parallel, merged in order: entries are newest first, so the first chunk
        // that has a group holds its newest match.
        let chunkSize = max(500, entries.count / ProcessInfo.processInfo.activeProcessorCount + 1)
        let chunks = await withTaskGroup(of: (Int, [String: PrivacyWarning]).self) { group in
            for start in stride(from: 0, to: entries.count, by: chunkSize) {
                let chunk = entries[start..<min(start + chunkSize, entries.count)]
                group.addTask { (start, warnings(in: chunk, detectors: detectors)) }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        var merged: [String: PrivacyWarning] = [:]
        for (_, warnings) in chunks.sorted(by: { $0.0 < $1.0 }) {
            for (id, warning) in warnings {
                if merged[id] == nil {
                    merged[id] = warning
                } else {
                    merged[id]?.occurrences += warning.occurrences
                }
            }
        }
        return result(Array(merged.values))
    }

    /// The warnings of `entries` by id.
    private static func warnings(in entries: Slice<LogEntries>,
                                 detectors: [PrivacyDetector]) -> [String: PrivacyWarning] {
        var groups: [String: PrivacyWarning] = [:]
        for entry in entries {
            // A cancelled scan stops early; LogR does not publish its partial result.
            if Task.isCancelled {
                break
            }
            // Values the developer marked private are not leaks: scan what an export would show.
            let entry = entry.redactingPrivateValues()
            func record(_ found: [Finding], in text: String, field: String) {
                for finding in found {
                    let detector = detectors[finding.detector]
                    let id = "\(entry.file):\(entry.line):\(detector.name)"
                    if groups[id] != nil {
                        groups[id]?.occurrences += 1
                    } else {
                        // Entries arrive newest first, so the first match is the newest.
                        groups[id] = PrivacyWarning(file: entry.file, line: entry.line, detector: detector.name,
                                                    severity: detector.severity, occurrences: 1,
                                                    excerpt: excerpt(of: text, around: finding.range,
                                                                     masking: found,
                                                                     detectors: detectors),
                                                    field: field)
                    }
                }
            }
            record(findings(in: entry.message, detectors: detectors), in: entry.message, field: "message")
            for (path, key, value) in metadataTexts(entry.metadata ?? [:]) {
                // `key=value`, so a value under a key such as `password` reads as a credential pair.
                let text = "\(key)=\(value)"
                let valueStart = text.utf8.index(text.startIndex, offsetBy: key.utf8.count + 1)
                record(findings(in: text, detectors: detectors).filter { $0.range.upperBound > valueStart },
                       in: text, field: path)
            }
        }
        return groups
    }

    struct Finding {
        let detector: Int
        let range: Range<String.Index>
    }

    /// Each detector's matches, earlier detectors claiming text first. Matches overlapping text an earlier
    /// detector claimed, or a privacy placeholder, are dropped.
    static func findings(in text: String, detectors: [PrivacyDetector]) -> [Finding] {
        var claimed = text.contains("<") ? placeholder.matches(in: text,
                                                               range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text) } : []
        var found: [Finding] = []
        for (index, detector) in detectors.enumerated() {
            for range in detector.matcher(text) where !range.isEmpty && range.lowerBound >= text.startIndex
                && range.upperBound <= text.endIndex && !claimed.contains(where: range.overlaps) {
                claimed.append(range)
                found.append(Finding(detector: index, range: range))
            }
        }
        return found
    }

    private static let placeholder = try! NSRegularExpression(pattern: "<private(?::[0-9a-f]{8})?>|<sensitive>")

    /// Up to 40 characters either side of `range`, with every finding in it replaced by `[detector name]`.
    static func excerpt(of text: String, around range: Range<String.Index>, masking found: [Finding],
                        detectors: [PrivacyDetector]) -> String {
        let lower = text.index(range.lowerBound, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
        let upper = text.index(range.upperBound, offsetBy: 40, limitedBy: text.endIndex) ?? text.endIndex
        var excerpt = lower > text.startIndex ? "…" : ""
        var cursor = lower
        for finding in found.sorted(by: { $0.range.lowerBound < $1.range.lowerBound })
            where finding.range.overlaps(lower..<upper) && finding.range.upperBound > cursor {
            if finding.range.lowerBound > cursor {
                excerpt += text[cursor..<finding.range.lowerBound]
            }
            excerpt += "[\(detectors[finding.detector].name)]"
            cursor = finding.range.upperBound
        }
        if cursor < upper {
            excerpt += text[cursor..<upper]
        }
        return excerpt + (max(cursor, upper) < text.endIndex ? "…" : "")
    }

    /// Every string and integer in `metadata` with its key path and innermost key, in key order.
    static func metadataTexts(_ metadata: [String: LogMetadataValue]) -> [(path: String, key: String,
                                                                           value: String)] {
        var texts: [(String, String, String)] = []
        func walk(_ value: LogMetadataValue, path: String, key: String) {
            switch value {
            case let .string(string): texts.append((path, key, string))
            case let .int(int): texts.append((path, key, String(int)))
            case let .array(values):
                for (index, value) in values.enumerated() {
                    walk(value, path: "\(path)[\(index)]", key: key)
                }
            case let .dictionary(dictionary):
                for (child, value) in dictionary.sorted(by: { $0.key < $1.key }) {
                    walk(value, path: "\(path).\(child)", key: child)
                }
            case .bool, .date, .double: break
            }
        }
        for (key, value) in metadata.sorted(by: { $0.key < $1.key }) {
            walk(value, path: key, key: key)
        }
        return texts
    }

    static func result(_ warnings: [PrivacyWarning]) -> PrivacyAnalysisResult {
        let warnings = warnings.sorted {
            ($1.severity.priority, $1.occurrences, $0.id) < ($0.severity.priority, $0.occurrences, $1.id)
        }
        let critical = warnings.count(where: { $0.severity == .critical })
        let high = warnings.count(where: { $0.severity == .high })
        let summary = warnings.isEmpty
            ? "No sensitive values found in the scanned logs."
            : "\(warnings.count == 1 ? "1 call site logs" : "\(warnings.count) call sites log") sensitive values: "
            + "\(critical) critical, \(high) high severity."
        return PrivacyAnalysisResult(warnings: warnings, summary: summary, criticalCount: critical,
                                     highCount: high)
    }
}
