//
//  PrivacyDetector.swift
//  Logr
//

import Foundation

/// One kind of sensitive value that ``LogRService/scanForPrivacyIssues(detectors:)`` looks for in messages and
/// metadata.
///
/// The scan runs detectors in array order, and text one detector matched is not offered to the ones after it, so
/// list specific detectors before general ones (``builtIn`` puts payment cards before phone numbers, and phone
/// numbers before high-entropy tokens). Matches that overlap a `<private>`, `<private:…>` or `<sensitive>`
/// placeholder, or a value the developer already marked private, are never reported.
///
/// ```swift
/// let ticket = PrivacyDetector(name: "Support ticket", severity: .medium) { text in
///     text.ranges(of: /TCK-[0-9]{6}/)
/// }
/// let result = await logger.scanForPrivacyIssues(detectors: PrivacyDetector.builtIn + [ticket])
/// ```
public struct PrivacyDetector: Sendable {
    /// Shown in warnings and used in their ``PrivacyWarning/id``, so keep it unique among the detectors of a scan.
    public let name: String
    /// The severity of every warning this detector raises.
    public let severity: LogSeverity
    /// The ranges of `text` holding a sensitive value; ranges outside `text` are ignored. Called once per message
    /// and once per string or integer metadata value, as `key=value` (the innermost key), off the main actor.
    public let matcher: @Sendable (_ text: String) -> [Range<String.Index>]

    public init(name: String,
                severity: LogSeverity,
                matcher: @escaping @Sendable (_ text: String) -> [Range<String.Index>]) {
        self.name = name
        self.severity = severity
        self.matcher = matcher
    }
}

public extension PrivacyDetector {
    /// Every built-in detector, most specific first.
    static let builtIn: [PrivacyDetector] = [
        paymentCard, jsonWebToken, apiKey, bearerToken, credential, emailAddress, iban, usSocialSecurityNumber,
        phoneNumber, ipAddress, coordinates, streetAddress, highEntropyToken
    ]

    /// 13-19 digits, written together or grouped by spaces or dashes as cards are printed (4-4-4-4, 4-6-5, ...),
    /// with a card brand prefix and a valid Luhn checksum. Neighbouring digit groups, such as an expiry date or a
    /// CVV, are not taken for part of the number.
    static let paymentCard = PrivacyDetector(name: "Payment card", severity: .critical) { text in
        guard text.utf8.count(where: \.isASCIIDigitByte) >= 13 else { return [] }
        return Patterns.digitGroups.ranges(in: text).flatMap { cardNumbers(in: text, run: $0) }
    }

    /// Three base64url parts separated by dots, the first starting with `eyJ` (`{"`).
    static let jsonWebToken = PrivacyDetector(name: "JSON Web Token", severity: .critical) { text in
        Patterns.jsonWebToken.ranges(in: text)
    }

    /// Keys with a well-known prefix: Stripe live (`sk_live_`), GitHub (`ghp_`, `github_pat_`), AWS (`AKIA`),
    /// Slack (`xoxa-`, `xoxb-`, `xoxp-`) and Google (`AIza`).
    static let apiKey = PrivacyDetector(name: "API key", severity: .critical) { text in
        Patterns.apiKey.ranges(in: text)
    }

    /// The value after `Bearer`, 16 characters or more.
    static let bearerToken = PrivacyDetector(name: "Bearer token", severity: .critical) { text in
        Patterns.bearerToken.ranges(in: text, group: 1)
    }

    /// The value of a `password`, `pwd`, `secret`, `api_key`, `token` (and similar) pair written with `=` or `:`,
    /// JSON included. Values such as `nil`, `***` or anything shorter than 3 characters are skipped. Token and key
    /// values need a digit, and a bare `token` needs `=` or JSON quotes, so prose such as `Token: expired` is not
    /// reported.
    static let credential = PrivacyDetector(name: "Credential", severity: .critical) { text in
        guard text.utf8.contains(UInt8(ascii: "=")) || text.utf8.contains(UInt8(ascii: ":")) else { return [] }
        return Patterns.credential.matches(in: text).compactMap { match in
            let key = match.groups[1].lowercased()
            let value = match.groups[3]
            guard value.count >= 3, !value.allSatisfy("*x•-.".contains),
                  !["nil", "null", "none", "true", "false", "undefined", "redacted", "hidden", "empty"]
                  .contains(value.lowercased()) else { return nil }
            if key.hasSuffix("token") || key.hasSuffix("key") {
                guard value.contains(where: \.isNumber) else { return nil }
                if key == "token", !match.groups[2].contains("="), !match.groups[2].contains("\"") {
                    return nil
                }
            }
            return value.startIndex..<value.endIndex
        }
    }

    /// Email addresses; asset names such as `icon@2x.png` are skipped.
    static let emailAddress = PrivacyDetector(name: "Email address", severity: .high) { text in
        guard text.utf8.contains(UInt8(ascii: "@")) else { return [] }
        return Patterns.email.ranges(in: text)
            .filter { Patterns.assetScale.firstMatch(in: String(text[$0])) == nil }
    }

    /// IBANs from a country of the IBAN registry, with the country's length and a valid mod-97 checksum.
    static let iban = PrivacyDetector(name: "IBAN", severity: .high) { text in
        guard text.utf8.count(where: \.isASCIIDigitByte) >= 8 else { return [] }
        return Patterns.ibanCandidate.ranges(in: text).compactMap { validIBAN(in: text, candidate: $0) }
    }

    /// `AAA-GG-SSSS` with the area, group and serial numbers the Social Security Administration issues.
    static let usSocialSecurityNumber = PrivacyDetector(name: "US Social Security number",
                                                        severity: .high) { text in
        guard text.utf8.contains(UInt8(ascii: "-")), text.utf8.count(where: \.isASCIIDigitByte) >= 9 else {
            return []
        }
        return Patterns.socialSecurityNumber.ranges(in: text)
    }

    /// Phone numbers `NSDataDetector` finds around runs of digits, spaces and `+()-.` with 7 digits or more (at
    /// most about 4,096 UTF-8 bytes of windows around such runs per text). Numbers written as digits alone, or
    /// with spaces alone unless a group of two digits or more starts with `0`, count only after a word such as
    /// `phone`, `tel` or `call`, or the key that ends right before them (`phone_number=`, `userPhone:`), so order
    /// numbers, timestamps and most lists of values are not reported.
    static let phoneNumber = PrivacyDetector(name: "Phone number", severity: .high) { text in
        guard let detector = Patterns.phoneDetector else { return [] }
        func digits(_ range: Range<String.Index>) -> Int {
            text[range].utf8.count(where: \.isASCIIDigitByte)
        }
        let windows = phoneWindows(in: text)
        // The rule runs follow, applied to the match: a run with a formatted number can hold a list of values.
        func isPhone(_ range: Range<String.Index>) -> Bool {
            guard (7...15).contains(digits(range)) else { return false }
            let match = text[range].utf8
            guard match.allSatisfy({ $0.isASCIIDigitByte || $0 == UInt8(ascii: " ") }),
                  !(match.contains(UInt8(ascii: " ")) && hasTrunkPrefix(text[range])) else { return true }
            return followsPhoneWord(text, range.lowerBound)
        }
        // Trust: 3 for a number with the country or area code the context cut off, 2 for a match within the
        // words of its window's run, 1 for one from a run read alone, 0 for one reaching into a neighbour's words.
        var matches: [(range: Range<String.Index>, trust: Int)] = []
        var fallbacks: [Range<String.Index>] = []
        for window in windows {
            // A match on no run was read from context alone.
            let found = detector.ranges(in: text, within: window.range).filter { match in
                windows.contains { match.overlaps($0.run) }
            }
            matches += found.filter(isPhone).map { ($0, window.words.clamped(to: $0) == $0 ? 2 : 0) }
            // The detector joins a number to digits around it, or cuts a prefix off after `/`; the run read alone
            // gives the number back.
            // The common case: the window's only match is its run, which read alone gives the same match.
            if found.filter({ $0.overlaps(window.run) }) == [window.run], digits(window.run) <= 15 {
                continue
            }
            let joined = found.contains(where: { digits($0) > 15 })
            for alone in detector.ranges(in: text, within: window.run).filter(isPhone) {
                // A country or area code the context cut off (`/+1 (567) 845-0887`).
                // A union over 15 digits took a neighbour in as well.
                if "+(".contains(text[alone.lowerBound]),
                   let cut = found.first(where: { $0.lowerBound > alone.lowerBound && $0.overlaps(alone) }),
                   case let union = alone.lowerBound..<max(alone.upperBound, cut.upperBound), digits(union) <= 15 {
                    matches.append((union, 3))
                } else if joined {
                    matches.append((alone, 1))
                } else if found.contains(where: { alone.overlaps($0) && isPhone($0) }) {
                    // A number dropped with the neighbour it was joined to (`6638; 12/26`).
                    fallbacks.append(alone)
                }
            }
        }
        // Neighbouring windows find a number twice, or a part of it: of overlapping matches, the most trusted
        // wins, then the longest one.
        func rank(_ match: (range: Range<String.Index>, trust: Int)) -> (Int, Int) {
            (match.trust, text.utf8.distance(from: match.range.lowerBound, to: match.range.upperBound))
        }
        var kept: [Range<String.Index>] = []
        for match in matches.sorted(by: { rank($0) > rank($1) })
            where !kept.contains(where: match.range.overlaps) {
            kept.append(match.range)
        }
        for alone in fallbacks where !kept.contains(where: alone.overlaps) {
            kept.append(alone)
        }
        return kept.sorted { $0.lowerBound < $1.lowerBound }
    }

    /// Public IPv4 and IPv6 addresses. Loopback, private, link-local, carrier-grade NAT, multicast, unspecified
    /// and IPv4-mapped addresses are skipped, as are four-part numbers right after `v`, `version`, `build` or an
    /// OS name.
    static let ipAddress = PrivacyDetector(name: "IP address", severity: .medium) { text in
        var ranges: [Range<String.Index>] = []
        if text.utf8.contains(UInt8(ascii: ".")), text.utf8.count(where: \.isASCIIDigitByte) >= 4 {
            ranges += Patterns.ipv4.ranges(in: text).filter { range in
                isPublicIPv4(String(text[range])) && !followsVersionWord(text, range)
            }
        }
        if text.utf8.count(where: { $0 == UInt8(ascii: ":") }) >= 2 {
            ranges += Patterns.ipv6Candidate.ranges(in: text).filter { isPublicIPv6(String(text[$0])) }
        }
        return ranges
    }

    /// A latitude and longitude with 4 decimals or more each, separated by a comma; pairs that are both under 1
    /// in magnitude (`0.1234, 0.5678`) are not reported.
    static let coordinates = PrivacyDetector(name: "Coordinates", severity: .medium) { text in
        guard text.utf8.contains(UInt8(ascii: ",")), text.utf8.count(where: \.isASCIIDigitByte) >= 10 else {
            return []
        }
        return Patterns.coordinates.matches(in: text).compactMap { match in
            guard let latitude = Double(match.groups[1]), let longitude = Double(match.groups[2]),
                  abs(latitude) <= 90, abs(longitude) <= 180, abs(latitude) >= 1 || abs(longitude) >= 1 else {
                return nil
            }
            return match.range
        }
    }

    /// Street addresses `NSDataDetector` finds in text with a number that starts a word and is followed by a
    /// capitalized word other than a month.
    static let streetAddress = PrivacyDetector(name: "Street address", severity: .medium) { text in
        guard Patterns.addressHint.firstMatch(in: text) != nil, let detector = Patterns.addressDetector else {
            return []
        }
        return detector.ranges(in: text)
    }

    /// Tokens of 20-64 base64 or base64url characters that mix upper case, lower case and digits, with a Shannon
    /// entropy of 4 bits per character or more. Hex strings and UUIDs are skipped, and so are runs longer than 64
    /// characters (URL paths included) and `data:` URL payloads. In a shorter run with `/`, each segment is judged
    /// alone.
    static let highEntropyToken = PrivacyDetector(name: "High-entropy token", severity: .medium) { text in
        tokenRuns(in: text).flatMap { run -> [Range<String.Index>] in
            guard text.utf8.distance(from: run.lowerBound, to: run.upperBound) <= 64,
                  !text[..<run.lowerBound].hasSuffix("base64,") else { return [] }
            return text[run].split(separator: "/").map { $0.startIndex..<$0.endIndex }
                .filter { isHighEntropy(text[$0]) }
        }
    }
}

// MARK: - Validation

private extension PrivacyDetector {
    /// The card numbers in `run`, each the longest run of whole digit groups starting at the first group not used
    /// yet that passes the brand and Luhn checks.
    static func cardNumbers(in text: String, run: Range<String.Index>) -> [Range<String.Index>] {
        let groups = text[run].split(whereSeparator: { $0 == " " || $0 == "-" })
        var cards: [Range<String.Index>] = []
        var first = groups.startIndex
        while first < groups.endIndex {
            // A group joined by `-` to the one before is the end of something else, such as a phone number.
            if first > groups.startIndex, text[text.index(before: groups[first].startIndex)] == "-" {
                first += 1
                continue
            }
            var digits: [Int] = []
            var end: Int?
            for last in first..<groups.endIndex {
                digits += groups[last].utf8.map { Int($0 - UInt8(ascii: "0")) }
                guard digits.count <= 19 else { break }
                if hasCardPrefix(digits), passesLuhn(digits), isCardGrouping(groups[first...last]) {
                    end = last
                }
            }
            if let end {
                cards.append(groups[first].startIndex..<groups[end].endIndex)
                first = end + 1
            } else {
                first += 1
            }
        }
        return cards
    }

    /// One group, or the groupings cards are printed with: 4-4-4-4(-3), 4-6-5 and 4-6-4. Phone numbers in a row
    /// (`415-555-2671 415-555-9876`) can otherwise pass the brand and Luhn checks by chance.
    static func isCardGrouping(_ groups: ArraySlice<Substring>) -> Bool {
        guard let first = groups.first, let last = groups.last, groups.count > 1 else { return true }
        return first.count == 4 && groups.dropFirst().dropLast().allSatisfy { $0.count == 4 || $0.count == 6 }
            && (3...6).contains(last.count)
    }

    static func hasCardPrefix(_ digits: [Int]) -> Bool {
        guard (13...19).contains(digits.count) else { return false }
        let two = digits[0] * 10 + digits[1]
        let three = two * 10 + digits[2]
        let four = three * 10 + digits[3]
        return digits[0] == 4 // Visa
            || (51...55).contains(two) || (2_221...2_720).contains(four) // Mastercard
            || two == 34 || two == 37 // American Express
            || four == 6_011 || (644...649).contains(three) || two == 65 // Discover
            || (3_528...3_589).contains(four) // JCB
            || (300...305).contains(three) || two == 36 || two == 38 || two == 39 // Diners Club
            || two == 62 // UnionPay
            || (2_200...2_204).contains(four) // Mir
            || [5_018, 5_020, 5_038, 5_893, 6_304, 6_759, 6_761, 6_762, 6_763].contains(four) // Maestro
    }

    static func passesLuhn(_ digits: [Int]) -> Bool {
        let sum = digits.reversed().enumerated().reduce(0) { sum, item in
            guard item.offset.isMultiple(of: 2) else {
                let doubled = item.element * 2
                return sum + (doubled > 9 ? doubled - 9 : doubled)
            }
            return sum + item.element
        }
        return sum.isMultiple(of: 10)
    }

    /// The candidate's first IBAN-length run of letters and digits when it checks out. The candidate pattern can
    /// run on into a following upper-case word (`… 00 EUR`), so only the country's length is taken.
    static func validIBAN(in text: String, candidate: Range<String.Index>) -> Range<String.Index>? {
        guard let length = Patterns.ibanLengths[String(text[candidate].prefix(2))] else { return nil }
        var characters: [Character] = []
        var end = candidate.lowerBound
        while end < candidate.upperBound, characters.count < length {
            if text[end] != " " {
                characters.append(text[end])
            }
            end = text.index(after: end)
        }
        guard characters.count == length else { return nil }
        // Mod-97 of the number formed by moving the first four characters to the end, letters as 10-35.
        var remainder = 0
        for character in characters.dropFirst(4) + characters.prefix(4) {
            guard let value = character.hexDigitValue ?? character.asciiValue.map({ Int($0) - 55 }) else {
                return nil
            }
            remainder = (remainder * (value > 9 ? 100 : 10) + value) % 97
        }
        return remainder == 1 ? candidate.lowerBound..<end : nil
    }

    static func isPublicIPv4(_ address: String) -> Bool {
        let octets = address.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ $0 <= 255 }) else { return false }
        switch (octets[0], octets[1]) {
        case (0, _), (10, _), (127, _), (169, 254), (192, 168), (224..., _): return false
        case (100, 64...127), (172, 16...31): return false
        default: return true
        }
    }

    static func isPublicIPv6(_ address: String) -> Bool {
        var bytes = in6_addr()
        guard inet_pton(AF_INET6, address, &bytes) == 1 else { return false }
        let raw = withUnsafeBytes(of: bytes) { Array($0) }
        // ::, ::1, IPv4-compatible and IPv4-mapped (the IPv4 detector judges the dotted part).
        if raw.prefix(10).allSatisfy({ $0 == 0 }) {
            return false
        }
        // Multicast, unique local, link-local.
        return !(raw[0] == 0xFF || raw[0] & 0xFE == 0xFC || (raw[0] == 0xFE && raw[1] & 0xC0 == 0x80))
    }

    /// Whether the word right before `range`, past spaces, `/`, `:` and `=`, is a version word or an OS name.
    static func followsVersionWord(_ text: String, _ range: Range<String.Index>) -> Bool {
        let before = text[..<range.lowerBound].reversed().drop { " /:=".contains($0) }
        let word = String(before.prefix(while: \.isLetter).reversed()).lowercased()
        return [
            "v",
            "ver",
            "version",
            "build",
            "os",
            "ios",
            "ipados",
            "macos",
            "tvos",
            "watchos",
            "visionos",
            "android"
        ].contains(word)
    }

    /// Whether a phone word (`phone`, `tel`, `call`...) ends within the 24 characters before `index`.
    static func followsPhoneWord(_ text: String, _ index: String.Index) -> Bool {
        let start = text.index(index, offsetBy: -24, limitedBy: text.startIndex) ?? text.startIndex
        // One character more is read, so a word the 24 characters cut (`Hotel`) does not start a word there.
        let context = start > text.startIndex ? text.index(before: start) : start
        let slice = String(text[context..<index])
        let skipped = text[context..<start].utf16.count
        return Patterns.phoneWord.firstMatch(in: slice, options: .withTransparentBounds,
                                             range: NSRange(location: skipped,
                                                            length: slice.utf16.count - skipped)) != nil
    }

    /// Whether a group of two digits or more starts with `0` (`06 12 34 56 78`, `020 7946 0958`), unlike a lone
    /// `0` in a list of values.
    static func hasTrunkPrefix(_ text: Substring) -> Bool {
        var previous = UInt8(ascii: " ")
        var beforePrevious = previous
        for byte in text.utf8 {
            if byte.isASCIIDigitByte, previous == UInt8(ascii: "0"), beforePrevious == UInt8(ascii: " ") {
                return true
            }
            beforePrevious = previous
            previous = byte
        }
        return false
    }

    /// Runs of 20 or more base64 and base64url characters; `=` padding ends a run.
    static func tokenRuns(in text: String) -> [Range<String.Index>] {
        var runs: [Range<String.Index>] = []
        var start: String.Index?
        var index = text.utf8.startIndex
        func close() {
            if let start, text.utf8.distance(from: start, to: index) >= 20 {
                runs.append(start..<index)
            }
            start = nil
        }
        while index < text.utf8.endIndex {
            let byte = text.utf8[index]
            if byte.isASCIIDigitByte || (65...90).contains(byte) || (97...122).contains(byte) || "+/_-".utf8
                .contains(byte) {
                start = start ?? index
            } else {
                close()
            }
            text.utf8.formIndex(after: &index)
        }
        close()
        return runs
    }

    static func isHighEntropy(_ token: Substring) -> Bool {
        let bytes = token.utf8.prefix { $0 != UInt8(ascii: "=") }
        guard (20...64).contains(bytes.count),
              bytes.contains(where: { (65...90).contains($0) }),
              bytes.contains(where: { (97...122).contains($0) }),
              bytes.contains(where: \.isASCIIDigitByte),
              UUID(uuidString: String(token)) == nil else { return false }
        return shannonEntropy(bytes) >= 4
    }

    static func shannonEntropy(_ bytes: some Collection<UInt8>) -> Double {
        var counts: [UInt8: Int] = [:]
        for byte in bytes {
            counts[byte, default: 0] += 1
        }
        let total = Double(bytes.count)
        return counts.values.reduce(0) { entropy, count in
            let probability = Double(count) / total
            return entropy - probability * log2(probability)
        }
    }
}

extension PrivacyDetector {
    /// Windows around the runs of digits, spaces and `+()-.` that could hold a phone number: 7 digits or more,
    /// written like one (`+` before a digit or `()-.` between digits, or spaces and a group like `06` or `020`) or
    /// after a phone word. A token glued to a letter by a digit or `-` at either end of a run (the digit groups of
    /// a UUID, `x415`) is left out of it; a run over 256 characters is cut between words. Each window is a run, or
    /// a part of one, with 16 characters of context on both sides, widened to whole words. The data detector slows
    /// down more than linearly with what it reads (about 200 µs a character on long runs of numbers), so windows
    /// stop once they cover about 4,096 UTF-8 bytes.
    static func phoneWindows(in text: String)
        -> [(range: Range<String.Index>, run: Range<String.Index>, words: Range<String.Index>)] {
        func isRunByte(_ byte: UInt8) -> Bool {
            byte.isASCIIDigitByte || " +()-.".utf8.contains(byte)
        }
        func isLetter(_ byte: UInt8) -> Bool {
            (65...90).contains(byte) || (97...122).contains(byte)
        }
        func gluesToLetter(_ byte: UInt8) -> Bool {
            byte.isASCIIDigitByte || byte == UInt8(ascii: "-")
        }
        let utf8 = text.utf8
        // A run can start or end inside a character (`\u{600}+1`, `1\u{301}`); windows must not. `index(after:)`
        // rounds down to the character first, in one pass over it: probing byte by byte is quadratic in its
        // length.
        func character(before index: String.Index) -> String.Index {
            index == text.endIndex ? index : text.index(before: text.index(after: index))
        }
        func character(after index: String.Index) -> String.Index {
            let lower = character(before: index)
            return lower == index ? index : text.index(after: lower)
        }
        // 16 characters, widened to whole words (48 at most): a token cut in two reads as a different number.
        func context(before index: String.Index) -> String.Index {
            var lower = character(before: index)
            var count = 0
            while lower > text.startIndex, count < 48,
                  count < 16 || !text[text.index(before: lower)].isWhitespace {
                text.formIndex(before: &lower)
                count += 1
            }
            return lower
        }
        func context(after index: String.Index) -> String.Index {
            var upper = character(after: index)
            var count = 0
            while upper < text.endIndex, count < 48, count < 16 || !text[upper].isWhitespace {
                text.formIndex(after: &upper)
                count += 1
            }
            return upper
        }
        let space = UInt8(ascii: " ")
        var windows: [(range: Range<String.Index>, run: Range<String.Index>, words: Range<String.Index>)] = []
        var budget = 4_096
        var index = utf8.startIndex
        while index < utf8.endIndex, budget > 0 {
            guard isRunByte(utf8[index]) else {
                utf8.formIndex(after: &index)
                continue
            }
            // Run bytes are ASCII, so run bounds fall on UTF-8 scalar boundaries.
            var start = index
            while index < utf8.endIndex, isRunByte(utf8[index]) {
                utf8.formIndex(after: &index)
            }
            var end = index
            let fullRun = character(before: start)..<character(after: end)
            if gluesToLetter(utf8[start]), start > utf8.startIndex, isLetter(utf8[utf8.index(before: start)]) {
                guard let gap = utf8[start..<end].firstIndex(of: space) else { continue }
                start = gap
            }
            if gluesToLetter(utf8[utf8.index(before: end)]), end < utf8.endIndex, isLetter(utf8[end]) {
                guard let gap = utf8[start..<end].lastIndex(of: space) else { continue }
                end = gap
            }
            while start < end, utf8[start] == space {
                utf8.formIndex(after: &start)
            }
            while start < end, utf8[utf8.index(before: end)] == space {
                utf8.formIndex(before: &end)
            }
            var digits = 0
            // `+` before a digit, or `()-.` between digits: a trailing `.` or `(ms)` does not make a list of
            // values (`100 200 400 800`, which the data detector reads as a number) look like a phone number.
            var punctuated = false
            var pendingPunctuation = false
            var previous = space
            for byte in utf8[start..<end] {
                if byte.isASCIIDigitByte {
                    punctuated = punctuated || pendingPunctuation || previous == UInt8(ascii: "+")
                    pendingPunctuation = false
                    digits += 1
                } else if byte != space, byte != UInt8(ascii: "+"), digits > 0 {
                    pendingPunctuation = true
                }
                previous = byte
            }
            guard digits >= 7, punctuated || hasTrunkPrefix(text[start..<end])
                || followsPhoneWord(text, start) else { continue }
            var part = start
            while part < end, budget > 0 {
                var partEnd = utf8.index(part, offsetBy: 256, limitedBy: end) ?? end
                if partEnd < end, let gap = utf8[part..<partEnd].lastIndex(of: space), gap > part {
                    partEnd = gap
                }
                let run = character(before: part)..<character(after: partEnd)
                // The run widened to whole words, the glued tokens left out of it included.
                var words = (part == start ? fullRun.lowerBound : run.lowerBound)
                    ..< (partEnd == end ? fullRun.upperBound : run.upperBound)
                let window = context(before: part)..<context(after: partEnd)
                while words.lowerBound > window.lowerBound,
                      !text[text.index(before: words.lowerBound)].isWhitespace {
                    words = text.index(before: words.lowerBound)..<words.upperBound
                }
                while words.upperBound < window.upperBound, !text[words.upperBound].isWhitespace {
                    words = words.lowerBound..<text.index(after: words.upperBound)
                }
                windows.append((window, run, words))
                budget -= utf8.distance(from: window.lowerBound, to: window.upperBound)
                part = partEnd
            }
        }
        return windows
    }
}

// MARK: - Patterns

private enum Patterns {
    static let digitGroups = regex("(?<![0-9])[0-9]+(?:[ -][0-9]+)*(?![0-9])")
    static let jsonWebToken =
        regex("(?<![A-Za-z0-9_-])eyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}")
    static let apiKey = regex("""
    (?<![A-Za-z0-9_])(?:sk_live_[0-9A-Za-z]{16,}|ghp_[0-9A-Za-z]{30,}|github_pat_[0-9A-Za-z_]{40,}\
    |AKIA[0-9A-Z]{16}|xox[abp]-[0-9A-Za-z-]{10,}|AIza[0-9A-Za-z_-]{35})(?![0-9A-Za-z_-])
    """)
    static let bearerToken = regex("(?i)\\bbearer\\s+([A-Za-z0-9._~+/-]{16,}=*)")
    static let credential = regex("""
    (?i)(?<![a-z0-9])(password|passwd|pwd|passphrase|client_secret|secret|api[_-]?key|access[_-]?token\
    |refresh[_-]?token|auth[_-]?token|token)("?\\s*[:=]\\s*"?)([^\\s"',;&<>{}()\\[\\]]+)
    """)
    /// Anchored and bounded: an unanchored local part retries from every position of a long run (quadratic).
    static let email = regex("""
    (?<![A-Za-z0-9._%+-])[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9-]{1,63}(?:\\.[A-Za-z0-9-]{1,63}){0,8}\\.[A-Za-z]{2,24}\
    (?![A-Za-z0-9-])
    """)
    static let assetScale = regex("@[0-9]x\\.")
    static let ibanCandidate = regex("(?<![A-Za-z0-9])[A-Z]{2}[0-9]{2}(?: ?[A-Z0-9]){11,30}(?![A-Za-z0-9])")
    static let socialSecurityNumber = regex("""
    (?<![0-9-])(?!000|666|9[0-9]{2})[0-9]{3}-(?!00)[0-9]{2}-(?!0000)[0-9]{4}(?![0-9-])
    """)
    /// A whole word, or the end of the `snake_case` or `camelCase` key right before the number (`phone_number=`,
    /// `userPhone:`, `"phoneNumber":"`); not `iPhone`, `callId=` or `isMobile=true userId=`.
    static let phoneWord: NSRegularExpression = {
        let words = "(?i:phones?|telephone|téléphone|telefon|tel|mobile|cell|cellphone|smartphone|"
            + "call|sms|whatsapp|fax)"
        let keyPart = "(?:(?<![\\p{L}\\p{N}_])|(?<=_)|(?<=[\\p{Ll}\\p{N}])(?<!i)(?=\\p{Lu}))"
        return regex("\\b\(words)\\b|\(keyPart)\(words)(?:_?(?i:numbers?|no|num|nr))?[^\\p{L}\\p{N}_(\\[@]*\\z")
    }()

    static let ipv4 = regex("(?<![A-Za-z0-9.])[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}(?![0-9]|\\.[0-9])")
    static let ipv6Candidate =
        regex("(?<![A-Za-z0-9:.])(?:[0-9A-Fa-f]{0,4}:){2,7}[0-9A-Fa-f]{0,4}(?![A-Za-z0-9:])")
    static let coordinates =
        regex("(?<![0-9.])(-?[0-9]{1,2}\\.[0-9]{4,})\\s*,\\s*(-?[0-9]{1,3}\\.[0-9]{4,})(?![0-9.])")
    /// Not before a month: every `Date` header has `27 Oct`.
    static let addressHint = regex("""
    (?<![A-Za-z0-9/._-])[0-9]{1,6}[A-Za-z]?,?\\s+(?!(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\\b)[A-Z][a-z]
    """)
    // `nil` only if the system lacks the detector types; the detectors then report nothing.
    static let phoneDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue)
    static let addressDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue)

    /// IBAN lengths by country, from the SWIFT IBAN registry.
    static let ibanLengths: [String: Int] = [
        "AD": 24, "AE": 23, "AL": 28, "AT": 20, "AZ": 28, "BA": 20, "BE": 16, "BG": 22, "BH": 22, "BR": 29,
        "BY": 28, "CH": 21, "CR": 22, "CY": 28, "CZ": 24, "DE": 22, "DK": 18, "DO": 28, "EE": 20, "EG": 29,
        "ES": 24, "FI": 18, "FO": 18, "FR": 27, "GB": 22, "GE": 22, "GI": 23, "GL": 18, "GR": 27, "GT": 28,
        "HR": 21, "HU": 28, "IE": 22, "IL": 23, "IQ": 23, "IS": 26, "IT": 27, "JO": 30, "KW": 30, "KZ": 20,
        "LB": 28, "LC": 32, "LI": 21, "LT": 20, "LU": 20, "LV": 21, "MC": 27, "MD": 24, "ME": 22, "MK": 19,
        "MR": 27, "MT": 31, "MU": 30, "NL": 18, "NO": 15, "PK": 24, "PL": 28, "PS": 29, "PT": 25, "QA": 29,
        "RO": 24, "RS": 22, "SA": 24, "SC": 31, "SE": 24, "SI": 19, "SK": 24, "SM": 27, "ST": 25, "SV": 28,
        "TL": 23, "TN": 24, "TR": 26, "UA": 29, "VA": 22, "VG": 24, "XK": 20
    ]

    static func regex(_ pattern: String) -> NSRegularExpression {
        // Fixed patterns: a typo fails every scanner test, never a user's input.
        try! NSRegularExpression(pattern: pattern)
    }
}

private extension NSRegularExpression {
    func ranges(in text: String, within window: Range<String.Index>) -> [Range<String.Index>] {
        matches(in: text, range: NSRange(window, in: text)).compactMap { Range($0.range, in: text) }
    }

    func ranges(in text: String, group: Int = 0) -> [Range<String.Index>] {
        matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range(at: group),
                                                                                           in: text) }
    }

    func matches(in text: String) -> [(range: Range<String.Index>, groups: [Substring])] {
        matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let groups = (0..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { text[$0] } ?? ""
            }
            return (range, groups)
        }
    }

    func firstMatch(in text: String) -> NSTextCheckingResult? {
        firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }
}

private extension UInt8 {
    var isASCIIDigitByte: Bool {
        (48...57).contains(self)
    }
}
