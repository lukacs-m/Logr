import CryptoKit
import Foundation
@testable import Logr
import Testing

private enum State { case idle }

private struct Described: CustomStringConvertible {
    var description: String { "described" }
}

private enum Failure: Error { case timeout }

@Suite("LogMessage")
struct LogMessageTests {
    typealias Kind = LogMessage.Redaction.Kind

    static let autoCases: [(String, LogMessage, String, Kind?)] = [
        ("String", "\("bob")", "bob", .private),
        ("String? nil", "\(String?.none)", "nil", .private),
        ("String? value", "\(String?.some("bob"))", "bob", .private),
        ("Int", "\(42)", "42", nil),
        ("UInt8", "\(UInt8(7))", "7", nil),
        ("Int? nil", "\(Int?.none)", "nil", nil),
        ("Int? value", "\(Int?.some(3))", "3", nil),
        ("Double", "\(2.5)", "2.5", nil),
        ("Float", "\(Float(1.5))", "1.5", nil),
        ("Double? nil", "\(Double?.none)", "nil", nil),
        ("Bool", "\(true)", "true", nil),
        ("Bool? value", "\(Bool?.some(false))", "false", nil),
        ("CustomStringConvertible", "\(Described())", "described", .private),
        ("Error", "\(Failure.timeout as any Error)", "timeout", .private),
        ("enum", "\(State.idle)", "idle", .private),
        ("metatype", "\(State.self)", "State", .private),
        ("Optional enum nil", "\(State?.none)", "nil", .private),
        ("Optional CustomStringConvertible", "\(Described?.some(Described()))", "described", .private)
    ]

    @Test(arguments: autoCases)
    func autoPrivacyFollowsOSLog(type: String, message: LogMessage, text: String, expected: Kind?) {
        #expect(message.text == text, "\(type)")
        #expect(message.redactions.map(\.kind) == (expected.map { [$0] } ?? []), "\(type)")
    }

    static let explicitCases: [(LogMessage, Kind?)] = [
        ("\("bob", privacy: .public)", nil),
        ("\(42, privacy: .private)", .private),
        ("\("bob", privacy: .private(mask: .hash))", .hashed),
        ("\(42, privacy: .sensitive)", .sensitive),
        ("\(State.idle, privacy: .public)", nil),
        ("\("bob", privacy: .auto)", .private),
        ("\(Int?.none, privacy: .private(mask: .hash))", .hashed)
    ]

    @Test(arguments: explicitCases)
    func explicitPrivacyWins(message: LogMessage, expected: Kind?) {
        #expect(message.redactions.map(\.kind) == (expected.map { [$0] } ?? []))
    }

    @Test func literalOnlyMessageHasNoValues() {
        let message: LogMessage = "Button tapped"
        #expect(message.text == "Button tapped")
        #expect(message.redactions.isEmpty)
    }

    @Test(arguments: [
        (LogPrivacy.public, Kind?.none),
        (.auto, .private),
        (.private, .private),
        (.private(mask: .hash), .hashed),
        (.sensitive, .sensitive)
    ])
    func existingString(privacy: LogPrivacy, expected: Kind?) {
        let message = LogMessage("token=abc", privacy: privacy)
        #expect(message.text == "token=abc")
        #expect(message.redactions.map(\.kind) == (expected.map { [$0] } ?? []))
    }

    @Test func rangesAreUTF8OffsetsInTheText() {
        let name = "Zoë"
        let message: LogMessage = "Café \(name) paid \(3) for \(name, privacy: .sensitive)"
        #expect(message.text == "Café Zoë paid 3 for Zoë")
        // "Café " is 6 bytes, "Zoë" 4.
        #expect(message.redactions.map(\.range) == [6..<10, 22..<26])
        #expect(message.redactions.map(\.kind) == [.private, .sensitive])
    }

    @Test func descriptionRedactsEveryValueThatIsNotPublic() {
        let message: LogMessage = """
        \("a@b.c") \(42) \("tok", privacy: .sensitive) \("id", privacy: .private(mask: .hash)) \("ok", privacy: .public)
        """
        #expect(message.description == "<private> 42 <sensitive> <private> ok")
    }
}

@Suite("LogMessage rendering")
struct LogMessageRenderingTests {
    let key = SymmetricKey(data: Data(repeating: 7, count: 32))

    @Test func keepingPrivateValuesLeavesThemInClearAndMarksThem() {
        let message: LogMessage = """
        \("tok", privacy: .sensitive) user \("Zoë") id \("u1", privacy: .private(mask: .hash)) n=\(3)
        """
        let rendered = message.rendered(keepingPrivateValues: true, hashKey: key)
        #expect(rendered.text == "<sensitive> user Zoë id u1 n=3")
        #expect(rendered.privateRanges == [17..<21, 25..<27])
    }

    @Test func redactingReplacesEveryValueAndMarksNothing() {
        let message: LogMessage = "user \("Zoë") card \("4111", privacy: .sensitive) n=\(3)"
        let rendered = message.rendered(keepingPrivateValues: false, hashKey: key)
        #expect(rendered.text == "user <private> card <sensitive> n=3")
        #expect(rendered.privateRanges.isEmpty)
    }

    @Test func hashedValuesCorrelateAndDependOnTheKey() throws {
        let first = LogMessage("u1", privacy: .private(mask: .hash)).rendered(keepingPrivateValues: false, hashKey: key)
        let again = LogMessage("u1", privacy: .private(mask: .hash)).rendered(keepingPrivateValues: false, hashKey: key)
        let other = LogMessage("u2", privacy: .private(mask: .hash)).rendered(keepingPrivateValues: false, hashKey: key)
        let otherKey = LogMessage("u1", privacy: .private(mask: .hash))
            .rendered(keepingPrivateValues: false, hashKey: SymmetricKey(data: Data(repeating: 8, count: 32)))

        let match = try #require(first.text.wholeMatch(of: /<private:([0-9a-f]{8})>/))
        let expected = HMAC<SHA256>.authenticationCode(for: Data("u1".utf8), using: key)
            .prefix(4).map { String(format: "%02x", $0) }.joined()
        #expect(match.1 == expected)
        #expect(first.text == again.text)
        #expect(first.text != other.text)
        #expect(first.text != otherKey.text)
    }

    @Test func hashedValuesWithoutAKeyArePrivate() {
        let message = LogMessage("u1", privacy: .private(mask: .hash))
        #expect(message.rendered(keepingPrivateValues: false, hashKey: nil).text == "<private>")
    }

    @Test func redactedRenderingNeverContainsAPrivateValue() {
        let secrets = ["alice@example.com", "4111 1111 1111 1111", "hunter2"]
        let message: LogMessage = """
        login \(secrets[0]) card \(secrets[1], privacy: .private(mask: .hash)) pw \(secrets[2], privacy: .sensitive)
        """
        let text = message.rendered(keepingPrivateValues: false, hashKey: key).text
        for secret in secrets {
            #expect(!text.contains(secret))
        }
    }

    @Test(arguments: [true, false])
    func mirrorPartsSplitAroundPrivateValuesOnly(hasKey: Bool) {
        let key = hasKey ? SymmetricKey(size: .bits256) : nil
        let message: LogMessage = """
        \("a")é \(1) \("b", privacy: .sensitive) \("c", privacy: .private(mask: .hash)) \("ü")
        """
        let redacted = message.rendered(keepingPrivateValues: false, hashKey: key).text
        let hashed = LogMessage("c", privacy: .private(mask: .hash)).rendered(keepingPrivateValues: false, hashKey: key)
        #expect(hashed.text.hasPrefix(hasKey ? "<private:" : "<private>"))
        #expect(message.mirrorParts(redacted: redacted, hashKey: key)
            == ["", "a", "é 1 <sensitive> \(hashed.text) ", "ü", ""])
        let only = LogMessage("only", privacy: .private)
        #expect(only.mirrorParts(redacted: only.description, hashKey: nil) == ["", "only", ""])
        #expect(("literal" as LogMessage).mirrorParts(redacted: "literal", hashKey: nil) == ["literal"])
    }
}
