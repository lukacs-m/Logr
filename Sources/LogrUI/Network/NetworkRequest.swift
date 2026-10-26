//
//  NetworkRequest.swift
//  LogrUI
//

import Logr
import LogrNetwork
import SwiftUI

/// An entry recorded by `NetworkLogger`, read back from its ``HTTPLogFields`` metadata.
struct NetworkRequest: Identifiable {
    let entry: LogEntry
    let method: String
    let url: String
    let host: String
    let path: String
    let status: Int?
    let durationMilliseconds: Double?
    let requestBytes: Int?
    let responseBytes: Int?

    var id: String {
        entry.id
    }

    /// `nil` for an entry `NetworkLogger` did not record.
    init?(_ entry: LogEntry) {
        guard entry.category == .http, let metadata = entry.metadata,
              case let .string(method)? = metadata[HTTPLogFields.method]
        else { return nil }
        self.entry = entry
        self.method = method
        url = metadata[HTTPLogFields.url]?.stringValue ?? ""
        // The query may hold a raw `<private>`, which `URL(string:)` rejects; host and path come before it.
        let components = URL(string: String(url.prefix { $0 != "?" && $0 != "#" }))
        host = components?.host() ?? ""
        let path = components?.path(percentEncoded: false) ?? ""
        self.path = path.isEmpty ? "/" : path
        status = metadata[HTTPLogFields.status].flatMap(Self.int)
        durationMilliseconds = metadata[HTTPLogFields.durationMilliseconds].flatMap(Self.double)
        requestBytes = metadata[HTTPLogFields.requestBytes].flatMap(Self.int)
        responseBytes = metadata[HTTPLogFields.responseBytes].flatMap(Self.int)
    }

    /// `NetworkLogger` records a cancelled request at `.notice` and any other failure at `.error`.
    var statusClass: HTTPStatusClass {
        switch status {
        case nil: entry.level == .notice ? .cancelled : .failed
        case let status? where status >= 500: .serverError
        case let status? where status >= 400: .clientError
        case let status? where status >= 300: .redirection
        case let status? where status >= 200: .success
        case let status? where status >= 100: .informational
        default: .failed
        }
    }

    var statusText: String {
        if let status {
            return String(status)
        }
        return statusClass == .cancelled ? String(localized: "Cancelled") : String(localized: "Failed")
    }

    var durationText: String? {
        durationMilliseconds.map { Self.milliseconds($0) }
    }

    static func milliseconds(_ value: Double) -> String {
        let digits = value < 10 ? 1 : 0
        return value.formatted(.number.precision(.fractionLength(digits))) + " ms"
    }

    static func bytes(_ count: Int) -> String {
        Int64(count).formatted(.byteCount(style: .file, spellsOutZero: false))
    }

    func headers(_ key: String) -> [(name: String, value: String)]? {
        guard case let .dictionary(headers)? = entry.metadata?[key] else { return nil }
        return headers.map { ($0.key, $0.value.stringValue) }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private static func int(_ value: LogMetadataValue) -> Int? {
        if case let .int(number) = value {
            return number
        }
        return nil
    }

    private static func double(_ value: LogMetadataValue) -> Double? {
        switch value {
        case let .double(number): number
        case let .int(number): Double(number)
        default: nil
        }
    }
}

/// The status filter of ``NetworkLogView``.
enum HTTPStatusClass: CaseIterable, Identifiable {
    case informational, success, redirection, clientError, serverError, failed, cancelled

    var id: Self {
        self
    }

    var title: LocalizedStringKey {
        switch self {
        case .informational: "1xx Informational"
        case .success: "2xx Success"
        case .redirection: "3xx Redirection"
        case .clientError: "4xx Client error"
        case .serverError: "5xx Server error"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }

    var tint: Color {
        switch self {
        case .informational: .teal
        case .success: .green
        case .redirection: .blue
        case .clientError: .orange
        case .failed, .serverError: .red
        case .cancelled: .gray
        }
    }
}
