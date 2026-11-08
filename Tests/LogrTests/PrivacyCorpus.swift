import Foundation
@testable import Logr

/// Inputs for `PrivacyScannerTests`: texts each built-in detector must flag, and texts no detector may flag.
enum PrivacyCorpus {
    /// A message and the one detector that must flag it.
    static let truePositives: [(String, String)] = [
        // Payment cards: 13-19 digits, a card brand prefix, Luhn.
        ("Charged card 4111 1111 1111 1111", PrivacyDetector.paymentCard.name),
        ("card=4111-1111-1111-1111 declined", PrivacyDetector.paymentCard.name),
        ("Saved 5555555555554444", PrivacyDetector.paymentCard.name),
        ("Amex 378282246310005 on file", PrivacyDetector.paymentCard.name),
        ("Discover 6011111111111117", PrivacyDetector.paymentCard.name),
        ("JCB 3530111333300000", PrivacyDetector.paymentCard.name),
        ("Mastercard 2223003122003222", PrivacyDetector.paymentCard.name),
        ("Mir 2200 0000 0000 0004", PrivacyDetector.paymentCard.name),
        ("Maestro 6304000000000000", PrivacyDetector.paymentCard.name),
        ("card 4111 1111 1111 1111 123", PrivacyDetector.paymentCard.name),
        ("card 4111 1111 1111 1111 12 26", PrivacyDetector.paymentCard.name),
        ("qty 2 4111 1111 1111 1111", PrivacyDetector.paymentCard.name),
        ("cards 4111111111111111 5555555555554444", PrivacyDetector.paymentCard.name),

        // JWTs.
        ("""
        token eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ\
        .SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c
        """, PrivacyDetector.jsonWebToken.name),

        // Bearer tokens.
        ("Authorization: Bearer abcdEFGH1234ijklMNOP5678", PrivacyDetector.bearerToken.name),
        ("sending bearer 9f8e7d6c5b4a39281706f5e4d3c2b1a0", PrivacyDetector.bearerToken.name),

        // Known API key prefixes.
        // Escaped so GitHub push protection does not read these fake keys as real secrets.
        ("Stripe key sk\u{5F}live_4eC39HqLyjWDarjtT1zdp7dc", PrivacyDetector.apiKey.name),
        ("GitHub ghp_16C7e42F292c6912E7710c838347Ae178B4a", PrivacyDetector.apiKey.name),
        ("PAT github_pat_11ABCDEFG0123456789_abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMN", PrivacyDetector.apiKey.name),
        ("AWS AKIAIOSFODNN7EXAMPLE", PrivacyDetector.apiKey.name),
        ("Slack xoxb\u{2D}123456789012-1234567890123-AbCdEfGhIjKlMnOpQrStUvWx", PrivacyDetector.apiKey.name),
        ("Maps AIzaSyDdI0hCZtE6vySjMm-WEfRq3CPzqKqqsHI", PrivacyDetector.apiKey.name),

        // Credential pairs.
        ("login password=hunter2", PrivacyDetector.credential.name),
        ("pwd: letmein", PrivacyDetector.credential.name),
        ("config secret = s3cr3tValue", PrivacyDetector.credential.name),
        (#"body {"password":"hunter2","user":"zoe"}"#, PrivacyDetector.credential.name),
        ("api_key=abc123def", PrivacyDetector.credential.name),
        ("client_secret: 8d9f0a", PrivacyDetector.credential.name),

        // Email addresses.
        ("Signed in as zoe@example.com", PrivacyDetector.emailAddress.name),
        ("contact first.last+tag@sub.example.co.uk today", PrivacyDetector.emailAddress.name),

        // Phone numbers: formatted, international, or next to a phone word.
        ("Call +1 (415) 555-2671 now", PrivacyDetector.phoneNumber.name),
        ("dialing 415-555-2671", PrivacyDetector.phoneNumber.name),
        ("mobile +33 6 12 34 56 78", PrivacyDetector.phoneNumber.name),
        ("phone: 4155552671", PrivacyDetector.phoneNumber.name),
        ("Call +1 (415) 555-2671 ext. 22 after 5", PrivacyDetector.phoneNumber.name),
        ("id=3F2504E0-4F89  415-555-2671", PrivacyDetector.phoneNumber.name),
        ("Tel.415.555.2671", PrivacyDetector.phoneNumber.name),
        ("No.415-555-2671 on file", PrivacyDetector.phoneNumber.name),
        ("née à Zürich, téléphone 4155552671", PrivacyDetector.phoneNumber.name),
        ("phone_number=4155552671", PrivacyDetector.phoneNumber.name),
        ("userPhone: 4155552671", PrivacyDetector.phoneNumber.name),
        ("phoneNumber=415 555 2671", PrivacyDetector.phoneNumber.name),
        ("PHONE_NO=4155552671", PrivacyDetector.phoneNumber.name),
        ("user_phone=4155552671", PrivacyDetector.phoneNumber.name),
        ("{\"phoneNumber\":\"4155552671\"}", PrivacyDetector.phoneNumber.name),
        ("telNo: 4155552671", PrivacyDetector.phoneNumber.name),
        ("call me at 4155552671", PrivacyDetector.phoneNumber.name),
        ("phone_number => 4155552671", PrivacyDetector.phoneNumber.name),
        ("phone_no.4155552671", PrivacyDetector.phoneNumber.name),
        ("06 12 34 56 78", PrivacyDetector.phoneNumber.name),

        // IBANs (mod-97).
        ("Refund to DE89 3704 0044 0532 0130 00", PrivacyDetector.iban.name),
        ("iban GB82WEST12345698765432", PrivacyDetector.iban.name),
        ("FR1420041010050500013M02606 debited", PrivacyDetector.iban.name),

        // US social security numbers.
        ("SSN 123-45-6789 verified", PrivacyDetector.usSocialSecurityNumber.name),

        // Public IP addresses.
        ("client 81.2.69.160 connected", PrivacyDetector.ipAddress.name),
        ("resolver 8.8.8.8", PrivacyDetector.ipAddress.name),
        ("peer 2a00:1450:4007:80e::200e", PrivacyDetector.ipAddress.name),
        ("from 2001:db8::8a2e:370:7334", PrivacyDetector.ipAddress.name),
        ("macOS 14.4.1.2 / 81.2.69.160", PrivacyDetector.ipAddress.name),

        // Coordinate pairs.
        ("location 48.858370, 2.294481", PrivacyDetector.coordinates.name),
        ("at (37.7749,-122.4194)", PrivacyDetector.coordinates.name),

        // Street addresses.
        ("Ship to 1 Infinite Loop, Cupertino, CA 95014", PrivacyDetector.streetAddress.name),
        ("Delivered to 350 Fifth Avenue, New York, NY 10118", PrivacyDetector.streetAddress.name),

        // High-entropy tokens.
        ("session key Zx9Kq2Lm8Np4Rt7Vw1Yb3Cd6Fg", PrivacyDetector.highEntropyToken.name),
        ("refresh R7tY2uI9oP4aS1dF6gH3jK8lZ5xC0vBn", PrivacyDetector.highEntropyToken.name)
    ]

    /// Messages no detector may flag.
    static let falsePositives: [String] = [
        "Error Domain=NSURLErrorDomain Code=-1009 \"The Internet connection appears to be offline.\"",
        // UUIDs.
        "request 3F2504E0-4F89-41D3-9A0C-0305E82C3301 done",
        "session 6ba7b810-9dad-11d1-80b4-00c04fd430c8 resumed",

        // Timestamps and dates.
        "at 2026-10-27T10:15:30.123Z",
        "Mon, 27 Oct 2026 10:15:30 GMT",
        "epoch 1761560130",
        "epoch ms 1761560130123",
        "epoch ns 1761560130123456789",
        "fired at 10:15:30",
        "due 27/10/2026 10:15",

        // Version and build numbers.
        "Logr 2.0.0 started",
        "iOS 26.0.1 (23A341)",
        "build 1.2.3.4",
        "version 10.0.0.1",
        "Xcode 27A266a",
        "swift-log@1.16.0 resolved",

        // Hex hashes and addresses.
        "sha256 e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        "sha1 da39a3ee5e6b4b0d3255bfef95601890afd80709",
        "md5 d41d8cd98f00b204e9800998ecf8427e",
        "commit d7e08da merged",
        #"ETag "33a64df551425fcc55e4d42a148795d9f25f89d4""#,
        "object at 0x0000600003a2c000",

        // Base64 payloads.
        """
        payload eyJpZCI6MTIzLCJpdGVtcyI6WyJhcHBsZSIsImJhbmFuYSIsImNoZXJyeSJdLCJjb3VudCI6Mywib2siOnRydWUsIm5hbWUiOiJm\
        cnVpdHMiLCJkZXNjcmlwdGlvbiI6IkEgbGlzdCBvZiBmcnVpdHMifQ==
        """,
        """
        thumbnail data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6\
        kgAAAABJRU5ErkJggg==
        """,

        // Phone-like order, invoice and tracking numbers.
        "Order 4155552671 shipped",
        "order #20261027-0042 created",
        "Invoice 0612345678 paid",
        "tracking 1Z999AA10123456784",
        "item 1234567 restocked",

        // Placeholders Logr and LogrNetwork write.
        "user <private> logged in",
        "token <sensitive> refreshed",
        "account <private:3f9a1c2e> synced",
        "login password=<private>",
        "Authorization: Bearer <private>",
        "email <private> phone <private> card <private>",

        // Local addresses and other look-alikes.
        "listening on 127.0.0.1:8080",
        "LAN peer 192.168.1.10",
        "gateway 10.0.0.1",
        "loopback ::1",
        "Wi-Fi a4:83:e7:12:34:56",
        "loaded icon@2x.png",
        "OSStatus -25308 (errSecInteractionNotAllowed)",
        "HTTP/1.1 200 OK",
        "wrote 1048576 bytes in 0.25 s",
        "progress 0.5, 0.75",
        "/Users/zoe/Library/Application Support/com.example/Logr/logr_entries.ndjson",
        "SELECT * FROM logs WHERE id = ?",
        "LogR.record(level:message:category:file:function:line:metadata:)",
        "x-request-id req_8f3a2b1c9d4e5f60",
        "retry with token=nil",
        "password: *** (hidden)",
        "sent with empty api_key=",
        "Expected token: identifier",
        "Using access_token: cached",
        "Token: expired",
        "Hotel booking 4155552671",
        "Intel build 4155552671",
        "iOS 17.4.1.2 detected",
        "took 0.1234, 0.5678 s",
        "redacted ****:****:****:****::200e",
        "mapped ::ffff:192.168.1.10",
        "grid 4 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1",
        "reset password=nil",
        "JSON parse: unexpected token: 0x7B at offset 12",
        "epochs 1761560130 - 1761560199",
        "retry delays 100 200 400 800 1600 ms",
        "latencies ms: 120 135 98 240 310 87",
        "rgb 255 128 64 alpha 255 128 64",
        "values: 101 102 103 104 105",
        "retry delays 100 200 400 800 1600.",
        "latencies 120 135 98 240 310 (ms)",
        "values: 101 102 103 104 105.",
        "rgb (255 128 64)",
        "sizes - 100 200 400 800 1600",
        "microphone session 4155552671",
        "iPhone17,2 serial 4155552671",
        "deviceType=iPhone 4155552671",
        "TELEMETRY 4155552671",
        "myiPhone 4155552671",
        "isMobile=true userId=4155552671",
        "callId=4155552671",
        "call_id=4155552671",
        "callStartedAt=1761560130",
        "onCallEnded 4155552671",
        "Hotel booking references: 4155552671",
        "1761560130; 12/26 - 1761560130",
        "handleCall(4155552671)",
        "onCall[1761560130]",
        "batch 0987654321 done",
        "count=0212345678",
        "latencies 120 0 98 240 310 (ms)",
        "rgb 0 128 255 0 64 128",
        "version 10 0 19045 2965",

        // Luhn-valid numbers without a card brand prefix.
        "epoch ms 1761560130102",
        "order 1000000000000008 shipped",

        // Identifiers with high entropy but no digits.
        "BGTaskSchedulerErrorDomain error",
        "ASAuthorizationAppleIDProvider credential state changed",

        // A base64 payload whose `/`-separated pieces are token-sized.
        "upload chunk pU3KGCUwux1tEyze1iN7LtkeP3IfyxlxF0SU1kk8nVw0YL4xIB5p/tqg7ui5mX9cfCmZ/a/lkyU81lSvTfrXFCegrrP+6SMvivIhH57"
            + "kkcWxC+y1Vjv8Hm+TQn7LyP4pVeXNjkbcjtS3wnZNKlpNdncG+F2GkAJK"
    ]

    /// Metadata no detector may flag: an entry as `LogrNetwork` records it.
    static let networkMetadata: [String: LogMetadataValue] = [
        "http.method": .string("GET"),
        "http.url": .string("https://api.example.com/v1/users/3F2504E0-4F89-41D3-9A0C-0305E82C3301/orders"
            + "?token=<private>&page=2"),
        "http.status": .int(200),
        "http.duration_ms": .double(123.4),
        "http.request_headers": .dictionary([
            "Authorization": .string("<private>"),
            "Cookie": .string("<private>"),
            "User-Agent": .string("LogRExample/1 CFNetwork/3826.500.111 Darwin/25.0.0"),
            "Accept": .string("application/json")
        ]),
        "http.response_headers": .dictionary([
            "Etag": .string(#"W/"5e15153d-120f""#),
            "Date": .string("Mon, 27 Oct 2026 10:15:30 GMT"),
            "Content-Type": .string("application/json; charset=utf-8"),
            "Set-Cookie": .string("<private>"),
            "X-Request-Id": .string("req_8f3a2b1c9d4e5f60")
        ]),
        "http.request_bytes": .int(512),
        "http.response_bytes": .int(1_048_576),
        "http.protocol": .string("h2"),
        "http.reused_connection": .bool(true),
        "http.body_id": .string("01761560130123456789-3F2504E0-4F89-41D3-9A0C-0305E82C3301"),
        "http.dns_ms": .double(1.2),
        "http.tls_ms": .double(18.0)
    ]
}
