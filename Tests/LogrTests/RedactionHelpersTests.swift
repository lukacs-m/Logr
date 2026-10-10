import Testing
import Logr

@Suite("Redaction helpers")
struct RedactionHelpersTests {
    @Test(arguments: [
        ("192.168.1.42", "***.***.***.42"),
        ("2001:0db8:85a3:0000:0000:8a2e:0370:7334", "****:****:****:****:****:****:****:7334"),
        ("2001:db8::8a2e:370:7334", "****:****::****:****:7334"),
        ("::1", "::1"),
        ("::ffff:192.168.1.42", "::****:***.***.***.42")
    ])
    func redactedIP(address: String, expected: String) {
        #expect(address.redactedIP() == expected)
    }

    @Test(arguments: [
        ("a@example.com", "***@example.com"),
        ("ab@example.com", "a***@example.com"),
        ("abc@example.com", "a***@example.com")
    ])
    func redactedEmail(email: String, expected: String) {
        #expect(email.redactedEmail() == expected)
    }

    @Test func redactedEmailCanHideTheDomain() {
        #expect("a@example.com".redactedEmail(showDomain: false) == "***@***")
    }

    @Test(arguments: [
        ("4111 1111 1111 1234", "**** **** **** 1234"),
        ("4111111111111234", "************1234"),
        ("1234", "****")
    ])
    func maskedCreditCard(card: String, expected: String) {
        #expect(card.maskedCreditCard() == expected)
    }

    @Test(arguments: [
        ("+1 (555) 123-4567", "+* (***) ***-4567"),
        ("555-1234", "***-1234")
    ])
    func redactedPhone(phone: String, expected: String) {
        #expect(phone.redactedPhone() == expected)
    }
}
