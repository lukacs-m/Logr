//
//  RedactionHelpers.swift
//  Logr
//
//

import Foundation
import CryptoKit

/// Utilities for redacting sensitive information in log messages.
///
/// `RedactionHelpers` provides extension methods on `String` to mask or redact
/// sensitive data such as emails, phone numbers, credit cards, and other PII
/// before logging.
///
/// ## Overview
///
/// Privacy-conscious logging is critical for compliance with regulations like GDPR
/// and PCI-DSS. These helpers make it easy to redact sensitive data while preserving
/// enough information for debugging.
///
/// ## Example
///
/// ```swift
/// logger.info("User email: \(email.redactedEmail())")
/// // Output: "User email: j***@example.com"
///
/// logger.info("Card: \(cardNumber.maskedCreditCard())")
/// // Output: "Card: ****-****-****-1234"
///
/// logger.info("Phone: \(phone.redactedPhone())")
/// // Output: "Phone: ***-***-5678"
/// ```
///
/// ## Topics
///
/// ### Email Redaction
/// - ``Swift/String/redactedEmail(showDomain:)``
///
/// ### Credit Card Redaction
/// - ``Swift/String/maskedCreditCard(visibleDigits:)``
///
/// ### Phone Number Redaction
/// - ``Swift/String/redactedPhone(visibleDigits:)``
///
/// ### IP Address Redaction
/// - ``Swift/String/redactedIP()``
///
/// ### Custom Redaction
/// - ``Swift/String/redacted(keeping:position:)``
/// - ``Swift/String/hashed(algorithm:)``

// MARK: - String Extensions for Redaction

public extension String {
    /// Redacts an email address while optionally preserving the domain.
    ///
    /// Keeps the first character of the local part and masks the rest.
    /// - Parameter showDomain: Whether to reveal the full domain. Defaults to `true`.
    /// - Returns: The redacted email string.
    func redactedEmail(showDomain: Bool = true) -> String {
        guard let atIndex = firstIndex(of: "@") else {
            return redacted(keeping: 1, position: .start)
        }
        
        let localPart = self[..<atIndex]
        let domainPart = self[index(after: atIndex)...]
        
        let redactedLocal = localPart.prefix(1) + (localPart.count > 1 ? "***" : "")
        let redactedDomain = showDomain ? String(domainPart) : "***"
        
        return "\(redactedLocal)@\(redactedDomain)"
    }
    
    /// Masks a credit card number preserving only the last few digits.
    ///
    /// Maintains formatting characters (spaces, dashes) for readability.
    /// - Parameter visibleDigits: Number of trailing digits to keep. Defaults to `4`.
    /// - Returns: The masked card string.
    func maskedCreditCard(visibleDigits: Int = 4) -> String {
        let digits = filter(\.isNumber)
        guard digits.count > visibleDigits else {
            return String(repeating: "*", count: count)
        }
        
        let maskCount = digits.count - visibleDigits
        var masked = 0
        
        return map { char in
            guard char.isNumber else { return "\(char)" }
            
            if masked < maskCount {
                masked += 1
                return "*"
            }
            return "\(char)"
        }.joined()
    }
    
    /// Redacts a phone number showing only the last few digits.
    /// - Parameter visibleDigits: Number of trailing digits to keep. Defaults to `4`.
    /// - Returns: The redacted phone number.
    func redactedPhone(visibleDigits: Int = 4) -> String {
        maskedCreditCard(visibleDigits: visibleDigits)
    }
    
    /// Redacts an IP address (IPv4 or IPv6).
    ///
    /// - Note: For IPv6, this assumes full notation without compression.
    /// - Returns: The redacted IP string.
    func redactedIP() -> String {
        if contains(":") {
            return redactedIPv6()
        } else if contains(".") {
            return redactedIPv4()
        }
        return redacted(keeping: 3, position: .end)
    }
    
    private func redactedIPv4() -> String {
        let parts = split(separator: ".")
        guard parts.count == 4, let last = parts.last else {
            return redacted(keeping: 3, position: .end)
        }
        return "***.***.***.\(last)"
    }
    
    private func redactedIPv6() -> String {
        let parts = split(separator: ":")
        guard let last = parts.last else { return "***" }
        let masked = Array(repeating: "****", count: parts.count - 1)
        return masked.joined(separator: ":") + ":\(last)"
    }
    
    /// Redacts a Social Security Number keeping only the last 4 digits.
    /// - Returns: The redacted SSN string.
    func redactedSSN() -> String {
        maskedCreditCard(visibleDigits: 4)
    }
    
    /// Redacts a string keeping characters at the start or end.
    /// - Parameters:
    ///   - count: Number of characters to keep visible.
    ///   - position: Whether to keep characters at `.start` or `.end`.
    /// - Returns: The redacted string.
    func redacted(keeping count: Int, position: RedactionPosition) -> String {
        let totalCount = self.count
        guard count > 0, totalCount > count else {
            return String(repeating: "*", count: totalCount)
        }
        
        let maskedCount = totalCount - count
        
        switch position {
        case .start:
            return prefix(count) + String(repeating: "*", count: maskedCount)
        case .end:
            return String(repeating: "*", count: maskedCount) + suffix(count)
        }
    }
    
    /// Creates a cryptographically secure one-way hash for logging.
    ///
    /// Useful for tracking identifiers across logs without exposing original values.
    /// - Parameter algorithm: The hash algorithm. Defaults to `.sha256Truncated`.
    /// - Returns: A hexadecimal hash string.
    func hashed(algorithm: HashAlgorithm = .sha256Truncated) -> String {
        guard let data = data(using: .utf8) else { return "invalid" }
        return algorithm.hash(data)
    }
    
    /// Returns a fully redacted string preserving length.
    /// - Returns: A string of asterisks.
    func fullyRedacted() -> String {
        String(repeating: "*", count: count)
    }
}

// MARK: - Supporting Types

/// Position for keeping visible characters during redaction.
public enum RedactionPosition: Sendable {
    case start, end
}

/// Hash algorithms for secure redaction.
public enum HashAlgorithm: Sendable {
    case sha256Truncated, sha256, md5
    
    func hash(_ data: Data) -> String {
        let hash: Data
        switch self {
        case .sha256, .sha256Truncated:
            hash = Data(SHA256.hash(data: data))
        case .md5:
            hash = Data(Insecure.MD5.hash(data: data))
        }
        
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        
        switch self {
        case .sha256Truncated:
            return String(hex.prefix(8))
        default:
            return hex
        }
    }
}
