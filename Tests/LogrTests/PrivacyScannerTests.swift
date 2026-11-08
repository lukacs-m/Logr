import Foundation
@testable import Logr
import LogrTesting
import Testing

@Suite("Privacy scanner")
struct PrivacyScannerTests {
    private static func entry(_ message: String,
                              file: String = "App/Checkout.swift",
                              line: Int = 10,
                              metadata: [String: LogMetadataValue]? = nil,
                              privateRanges: [Range<Int>] = []) -> LogEntry {
        LogEntry(level: .info, category: .network, subsystem: "tests", message: message, file: file, line: line,
                 metadata: metadata, privateRanges: privateRanges)
    }

    private static func scan(_ entries: [LogEntry],
                             detectors: [PrivacyDetector] = PrivacyDetector.builtIn) async -> PrivacyAnalysisResult {
        await PrivacyScanner.scan(LogEntries(entries), detectors: detectors)
    }

    @Test(arguments: PrivacyCorpus.truePositives)
    func flagsSensitiveValue(message: String, detector: String) async {
        let result = await Self.scan([Self.entry(message)])
        #expect(result.warnings.map(\.detector) == [detector], "\(message)")
    }

    @Test(arguments: PrivacyCorpus.falsePositives)
    func ignoresLookAlike(message: String) async {
        let result = await Self.scan([Self.entry(message)])
        #expect(result.warnings.isEmpty, "\(result.warnings.map { "\($0.detector): \($0.excerpt)" })")
    }

    @Test func ignoresNetworkMetadata() async {
        let result = await Self.scan([Self.entry("GET /v1/users → 200 (123 ms)", metadata: PrivacyCorpus.networkMetadata)])
        #expect(result.warnings.isEmpty, "\(result.warnings.map { "\($0.field): \($0.excerpt)" })")
    }

    @Test func valuesMarkedPrivateAreNotLeaks() async {
        let message = "Signed in zoe@example.com with card 4111 1111 1111 1111"
        let email = 10..<25
        let card = 36..<55
        #expect(await Self.scan([Self.entry(message, privateRanges: [email, card])]).isEmpty)
        #expect(await Self.scan([Self.entry(message, privateRanges: [email])]).warnings.map(\.detector)
            == [PrivacyDetector.paymentCard.name])
    }

    @Test func scansMetadataWithKeyPaths() async {
        let metadata: [String: LogMetadataValue] = [
            "password": .string("hunter2"),
            "user": .dictionary(["contact": .array([.string("x"), .string("zoe@example.com")])]),
            "card": .int(4_111_111_111_111_111),
            "ratio": .double(48.858370)
        ]
        let result = await Self.scan([Self.entry("Profile updated", metadata: metadata)])

        let found = Dictionary(uniqueKeysWithValues: result.warnings.map { ($0.detector, $0) })
        #expect(found.count == 3)
        #expect(found[PrivacyDetector.credential.name]?.field == "password")
        #expect(found[PrivacyDetector.credential.name]?.excerpt == "password=[Credential]")
        #expect(found[PrivacyDetector.emailAddress.name]?.field == "user.contact[1]")
        #expect(found[PrivacyDetector.emailAddress.name]?.excerpt == "contact=[Email address]")
        #expect(found[PrivacyDetector.paymentCard.name]?.field == "card")
    }

    @Test func metadataKeysAreNotScannedAsValues() async {
        let result = await Self.scan([Self.entry("ok", metadata: ["zoe@example.com": .bool(true),
                                                                  "admin@example.com": .string("yes")])])
        #expect(result.isEmpty)
    }

    @Test func groupsByCallSiteAndDetector() async {
        let result = await Self.scan([
            Self.entry("to zoe@example.com", line: 1),
            Self.entry("to bob@example.com and amy@example.com", line: 1),
            Self.entry("to ann@example.com", line: 2),
            Self.entry("card 4111111111111111", line: 3),
            Self.entry("from 81.2.69.160 by ann@example.com", line: 2)
        ])

        #expect(result.warnings.map(\.id) == [
            "App/Checkout.swift:3:Payment card",
            "App/Checkout.swift:1:Email address",
            "App/Checkout.swift:2:Email address",
            "App/Checkout.swift:2:IP address"
        ])
        #expect(result.warnings.map(\.occurrences) == [1, 3, 2, 1])
        #expect(result.criticalCount == 1)
        #expect(result.highCount == 2)
        #expect(result.summary == "4 call sites log sensitive values: 1 critical, 2 high severity.")
    }

    @Test func excerptComesFromTheNewestEntry() async {
        // `recentLogs` is newest first.
        let result = await Self.scan([Self.entry("newest zoe@example.com"), Self.entry("oldest bob@example.com")])
        #expect(result.warnings.first?.excerpt == "newest [Email address]")
    }

    @Test func chunksMergeIntoExactCountsAndTheNewestExcerpt() async {
        // Enough entries for several parallel chunks; the newest entry is first.
        let entries = [Self.entry("newest zoe@example.com")]
            + (1..<5_000).map { Self.entry("older user\($0)@example.com card 4111111111111111") }

        let result = await Self.scan(entries)

        #expect(result.warnings.map(\.detector) == [PrivacyDetector.paymentCard.name, PrivacyDetector.emailAddress.name])
        #expect(result.warnings.map(\.occurrences) == [4_999, 5_000])
        #expect(result.warnings.last?.excerpt == "newest [Email address]")
    }

    @Test func excerptMasksEveryValueAndTrimsLongText() async throws {
        let message = String(repeating: "a", count: 50) + " zoe@example.com called +1 (415) 555-2671 "
            + String(repeating: "b", count: 50)
        let result = await Self.scan([Self.entry(message)])

        let email = try #require(result.warnings.first { $0.detector == PrivacyDetector.emailAddress.name })
        #expect(email.excerpt == "…" + String(repeating: "a", count: 39)
            + " [Email address] called [Phone number] " + String(repeating: "b", count: 14) + "…")
        #expect(result.warnings.allSatisfy { !$0.excerpt.contains("zoe@") && !$0.excerpt.contains("555") })
    }

    @Test func earlierDetectorsClaimText() async {
        let everything = PrivacyDetector(name: "Everything", severity: .low) { text in [text.startIndex..<text.endIndex] }

        let first = await Self.scan([Self.entry("zoe@example.com")], detectors: [everything] + PrivacyDetector.builtIn)
        #expect(first.warnings.map(\.detector) == ["Everything"])

        let last = await Self.scan([Self.entry("zoe@example.com")], detectors: PrivacyDetector.builtIn + [everything])
        #expect(last.warnings.map(\.detector) == [PrivacyDetector.emailAddress.name])
    }

    @Test func customDetectorsCannotMatchPlaceholders() async {
        let angle = PrivacyDetector(name: "Angle", severity: .low) { text in
            text.ranges(of: "<").map { $0.lowerBound..<text.index(after: $0.lowerBound) }
        }
        let result = await Self.scan([Self.entry("a <private> b <sensitive> c <private:3f9a1c2e> d <x")],
                                     detectors: [angle])
        #expect(result.warnings.first?.occurrences == 1)
        #expect(result.warnings.first?.excerpt.hasSuffix("<private:3f9a1c2e> d [Angle]x") == true)
    }

    @Test(.timeLimit(.minutes(1)))
    func longTextScansInLinearTime() async {
        // Quadratic patterns take minutes on 100,000 characters; linear ones take milliseconds.
        let blob = String(repeating: "a", count: 50_000) + "@" + String(repeating: "a.", count: 25_000)
        #expect(await Self.scan([Self.entry(blob)]).isEmpty)
        // The data detector slows down more than linearly with the length of what it reads.
        let lists = String(repeating: String(repeating: "1-2 ", count: 60) + "a ", count: 400)
        _ = await Self.scan([Self.entry(lists), Self.entry(String(repeating: "123 ", count: 25_000))])
        // A run next to a long grapheme cluster (combining or prepended marks) must not cost its length squared.
        let marks = String(repeating: "\u{301}", count: 32_000)
        let prepended = String(repeating: "\u{600}", count: 32_000)
        let clusters = await Self.scan([Self.entry("call 415-555-2671" + marks), Self.entry(prepended + "+1 (415) 555-2671")])
        #expect(clusters.warnings.first?.occurrences == 1)
    }

    @Test func rangesOutsideTheTextAreIgnored() async {
        // Ranges computed on a transformed copy of the text: lowercasing "İ" changes its UTF-8 length.
        let foreign = PrivacyDetector(name: "Foreign", severity: .low) { text in
            let lowered = text.lowercased()
            return lowered.ranges(of: "x")
        }
        let result = await Self.scan([Self.entry("İİİİİİİİ x")], detectors: [foreign])
        #expect(result.isEmpty)
    }

    @Test func phoneNumbersInLongRunsAreFound() async {
        let list = await Self.scan([Self.entry("Phones: 415-555-2671 415-555-9876 415-555-1234")])
        #expect(list.warnings.first?.occurrences == 3)
        let spaced = await Self.scan([Self.entry("(415) 555-2671" + String(repeating: " ", count: 30) + "(415) 555-9876")])
        #expect(spaced.warnings.first?.occurrences == 2)
        // Numbers before a phone number take part of the window budget, not all of it.
        let thirty = "Phones: " + (0..<30).map { "415-555-\(2600 + $0)" }.joined(separator: ", ")
        #expect(PrivacyDetector.phoneNumber.matcher(thirty).count == 30)
        let json = "{" + (1...11).map { "\"v\($0)\":\($0).2345678" }.joined(separator: ",") + "} contact 415-555-2671"
        #expect(PrivacyDetector.phoneNumber.matcher(json).count == 1)
        // Column padding is not part of a run, so it does not use up the budget.
        let pad = String(repeating: " ", count: 120)
        let padded = (0..<30).map { pad + "415-555-\(2600 + $0)" + pad }.joined(separator: ",")
        #expect(PrivacyDetector.phoneNumber.matcher("Phones: " + padded).count == 30)
    }

    @Test func phoneListsAreFound() async {
        let six = (1...6).map { "415-555-\(2670 + $0)" }.joined(separator: " ")
        #expect(PrivacyDetector.phoneNumber.matcher("Phones: " + six).count == 6)
        let list = await Self.scan([Self.entry("Phones: " + six)])
        #expect(list.warnings.first?.occurrences == 6)
        #expect(list.warnings.first?.excerpt.contains("555") == false)
        // A neighbour's window can misread a number; it is kept from the window that reads it whole.
        let slashed = "Phones: +1 (758) 500-8688 / +49 30 817996 / +1 (699) 345-9231 / 06 59 14 78 19"
        #expect(PrivacyDetector.phoneNumber.matcher(slashed).map { String(slashed[$0]) }.contains("06 59 14 78 19"))
        // Spaces padding a run do not count towards its length.
        let padded = String(repeating: " ", count: 1_100) + "+1 (415) 555-2671"
        #expect(PrivacyDetector.phoneNumber.matcher(padded).count == 1)
    }

    /// Phone numbers among the kinds of text logs hold, with a fixed seed: the windows read no worse than the data
    /// detector over the whole text. Every number it finds whole is found whole, every match is a number or one it
    /// reports too, and matches never overlap.
    @Test func phoneNumbersAmongLogText() throws {
        let detector = try #require(try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue))
        let phones = ["+1 (415) 555-2671", "415-555-2671", "+33 6 12 34 56 78", "+44 20 7946 0958",
                      "(212) 555-0199 ext. 22", "06 12 34 56 78", "+1 415 555 2671x22", "+49 30 993269"]
        let others = ["2026-10-28 10:15:30", "v1.2.3", "192.168.1.10", "$1,299.99", "id=3F2504E0-4F89", "item 1234567",
                      "error", "retry", "=>", "Zoë", "東京", "user", "ok", "42", "7", "1999", "x", ","]
        let separators = [" ; ", " / ", "/", ": ", "\n", " | ", " "]
        var seed: UInt64 = 0x5EED
        func next(_ bound: Int) -> Int {
            // SplitMix64: the same inputs on every run.
            seed &+= 0x9E37_79B9_7F4A_7C15
            var z = seed
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return Int((z ^ (z >> 31)) % UInt64(bound))
        }
        for _ in 0..<1_500 {
            let pieces = (0..<(1 + next(10))).map { _ in next(3) == 0 ? phones[next(phones.count)] : others[next(others.count)] }
            let text = pieces.joined(separator: separators[next(separators.count)])
            let found = PrivacyDetector.phoneNumber.matcher(text)
            let strings = found.map { String(text[$0]) }
            let whole = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .compactMap { Range($0.range, in: text) }
                .filter { (7...15).contains(text[$0].count(where: \.isNumber)) }
            for phone in Set(pieces).intersection(phones) where whole.contains(where: { text[$0].contains(phone) }) {
                #expect(strings.contains { $0.contains(phone) }, "\(phone) in \(text): \(strings)")
            }
            for match in found where !phones.contains(where: { text[match].contains($0) || $0.contains(text[match]) }) {
                #expect(whole.contains { $0.overlaps(match) }, "\(text[match]) in \(text)")
            }
            #expect(zip(found, found.dropFirst()).allSatisfy { $0.upperBound <= $1.lowerBound }, "\(text)")
        }
    }

    @Test func phoneWindowsStayWithinTheirBudget() {
        // Many phone-like runs, each with its context.
        let text = String(repeating: "415-555-2671 a ", count: 2_000)
        let covered = PrivacyDetector.phoneWindows(in: text)
            .reduce(0) { $0 + text.utf8.distance(from: $1.range.lowerBound, to: $1.range.upperBound) }
        #expect(covered > 0)
        #expect(covered <= 4_096 + 256 + 96)
        let dump = String(repeating: "1-2 ", count: 25_000)
        let dumped = PrivacyDetector.phoneWindows(in: dump)
            .reduce(0) { $0 + dump.utf8.distance(from: $1.range.lowerBound, to: $1.range.upperBound) }
        #expect(dumped <= 4_096 + 256 + 96)
    }

    @Test func idsBeforeAPhoneNumberDoNotHideIt() async {
        // Enough ids to use up the 4,096-character window budget if digits-only runs were windowed.
        let ids = (0..<150).map { "order \(1_000_000 + $0)" }.joined(separator: ", ")
        let result = await Self.scan([Self.entry(ids + ", call +1 (415) 555-2671")])
        #expect(result.warnings.map(\.detector) == [PrivacyDetector.phoneNumber.name])
    }

    @Test(.timeLimit(.minutes(1)))
    func bridgedTextScansInLinearTime() async {
        // A UTF-16 backed string from Foundation: offsetting from its start for every run was quadratic.
        let bridged = (String(repeating: "x 1234567 y ", count: 40_000) as NSString).appending(" é") as String
        #expect(await Self.scan([Self.entry(bridged)]).isEmpty)
    }

    static let wholeNumbers: [(String, [String])] = [
        ("Contact: 06 12 34 56 78", ["06 12 34 56 78"]),
        ("Tél : 01 23 45 67 89", ["01 23 45 67 89"]),
        ("at 10:30 06 12 34 56 78", ["06 12 34 56 78"]),
        ("+1-415-555-2671;ext=22", ["+1-415-555-2671"]),
        ("call +1 415 555 2671x22", ["+1 415 555 2671x22"]),
        ("Call +1 (415) 555-2671 ext. 22 after 5", ["+1 (415) 555-2671 ext. 22"]),
        // The data detector leaves out a country or area code right after a `/`.
        ("+49 30 993269/+1 (567) 845-0887", ["+49 30 993269", "+1 (567) 845-0887"]),
        ("ok/+1 (415) 555-2671/+44 20 7946 0958/user", ["+1 (415) 555-2671", "+44 20 7946 0958"]),
        ("v1.2.3/(212) 555-0199 ext. 22", ["(212) 555-0199 ext. 22"]),
        // The detector joins a number to its neighbour, which wins the overlap.
        ("+81 3-8904-6638; 12/26 - 798-836-9035", ["+81 3-8904-6638", "798-836-9035"]),
        ("phone/(749) 338-5251 ext. 26  0558 9701 - 2026-10-15 11:12:26.313 +0000", ["(749) 338-5251"]),
        ("v1.2.3 (212) 555-0199 ext. 22 1999 +1 415 555 2671x22 $1,299.99 7 +49 30 993269 id=3F2504E0-4F89",
         ["+1 415 555 2671x22", "+49 30 993269"])
    ]

    @Test func valuesBesideAPhoneNumberAreNotReported() {
        let text = "latencies 100 200 400 800 call +1 (415) 555-2671"
        #expect(PrivacyDetector.phoneNumber.matcher(text).map { String(text[$0]) } == ["+1 (415) 555-2671"])
        // In one run with a formatted number, a list of values still needs a phone word or a `0` group.
        let run = "sizes 100 200 400 415-555-2671"
        #expect(PrivacyDetector.phoneNumber.matcher(run).map { String(run[$0]) } == ["415-555-2671"])
    }

    @Test(arguments: wholeNumbers)
    func phoneNumbersAreReadWhole(text: String, numbers: [String]) throws {
        // Every digit of each number is inside a match: none is left in clear.
        let found = PrivacyDetector.phoneNumber.matcher(text)
        for number in numbers {
            let range = try #require(text.range(of: number))
            let clear = text[range].indices.filter { index in
                text[index].isNumber && !found.contains { $0.contains(index) }
            }
            #expect(clear.isEmpty, "\(number): \(found.map { String(text[$0]) })")
        }
    }

    @Test func aLongPhoneListIsRead() {
        let list = "Phones: " + (10..<30).map { "415-555-26\($0)" }.joined(separator: " ")
        #expect(PrivacyDetector.phoneNumber.matcher(list).count == 20)
    }

    @Test(arguments: ["\u{0600}+1 (415) 555-2671 x", "\u{0600}(415) 555-2671", "\u{06DD}+1 (415) 555-2671",
                      "\u{0600}06 12 34 56 78", "+1 (415) 555-2671\u{301} x"])
    func textStartingOrEndingMidCharacterDoesNotCrash(text: String) {
        _ = PrivacyDetector.phoneNumber.matcher(text)
    }

    @Test func aCardDoesNotTakeTheEndOfAPhoneNumber() async {
        // `2671 3056 320615` passes the brand and Luhn checks: a card cannot start right after a `-`.
        let adjacent = "call 415-555-2671 3056 320615 0287 ok"
        #expect(PrivacyDetector.paymentCard.matcher(adjacent).map { String(adjacent[$0]) } == ["3056 320615 0287"])
        let result = await Self.scan([Self.entry("call 415-555-2671, card 3056 320615 0287 ok")])
        #expect(Set(result.warnings.map(\.detector))
            == [PrivacyDetector.paymentCard.name, PrivacyDetector.phoneNumber.name])
        #expect(result.warnings.allSatisfy { !$0.excerpt.contains("2671") && !$0.excerpt.contains("0287") })
    }

    @Test func aCodeCutOffBeforeACardKeepsThePhoneNumber() async {
        // Read in context, `+81 3-8904-6638 4111 1111` is one number; the card would then claim the phone number.
        let result = await Self.scan([Self.entry("contact/+81 3-8904-6638 4111 1111 1111 1111 ok")])
        #expect(Set(result.warnings.map(\.detector))
            == [PrivacyDetector.paymentCard.name, PrivacyDetector.phoneNumber.name])
        #expect(result.warnings.allSatisfy { !$0.excerpt.contains("6638") })
        let text = "x/(212) 555-0199 ext. 22 1761560130"
        #expect(PrivacyDetector.phoneNumber.matcher(text).map { String(text[$0]) } == ["(212) 555-0199"])
    }

    @Test func everyCardInARunIsCountedAndMasked() async {
        let result = await Self.scan([Self.entry("cards 4111 1111 1111 1111 5555 5555 5555 4444")])
        #expect(result.warnings.map(\.detector) == [PrivacyDetector.paymentCard.name])
        #expect(result.warnings.first?.occurrences == 2)
        #expect(result.warnings.first?.excerpt == "cards [Payment card] [Payment card]")
    }

    @Test @MainActor func aCancelledScanIsNotPublished() async {
        let logger = LogR(cryptoService: LoggerCryptoService(store: InMemoryKeychainStore()),
                          configuration: LogrConfiguration(mirrorToOSLog: false))
        logger.info("Contact \("zoe@example.com", privacy: .public)")

        let scan = Task { await logger.scanForPrivacyIssues() }
        scan.cancel()
        _ = await scan.value

        #expect(logger.privacyAnalysisResult == nil)
    }

    @Test func emptyLogsScanClean() async {
        let result = await Self.scan([])
        #expect(result.isEmpty)
        #expect(result.summary == "No sensitive values found in the scanned logs.")
    }

    @Test @MainActor func logRPublishesTheResult() async {
        let logger = LogR(cryptoService: LoggerCryptoService(store: InMemoryKeychainStore()),
                          configuration: LogrConfiguration(mirrorToOSLog: false, storesPrivateValues: true))
        logger.info("Contact \("zoe@example.com", privacy: .public)")
        logger.info("Contact \("bob@example.com")")

        let result = await logger.scanForPrivacyIssues()

        #expect(result.warnings.map(\.occurrences) == [1])
        #expect(logger.privacyAnalysisResult == result)
    }
}
