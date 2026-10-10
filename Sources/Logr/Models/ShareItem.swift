//
//  ShareItem.swift
//  Logr
//
//  Created by martin on 23/11/2025.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Share Item

/// An export payload that advertises its JSON, CSV, or plain-text type to native sharing and saving.
///
/// The payload can be held in memory or produced when the system asks for it, so a large export is
/// only serialized once the user picks a share or save destination.
public struct ShareItem: Transferable {
    public let fileName: String
    let contentType: UTType
    private let payload: @Sendable () async throws -> Data

    public init(data: Data, fileName: String, contentType: UTType) {
        self.init(fileName: fileName, contentType: contentType) { data }
    }

    /// Creates an item whose bytes are serialized on demand, when the system requests them.
    package init(fileName: String,
                 contentType: UTType,
                 payload: @escaping @Sendable () async throws -> Data) {
        self.fileName = fileName
        self.contentType = contentType
        self.payload = payload
    }

    public static var transferRepresentation: some TransferRepresentation {
        // CSV conforms to plain text; prefer the exact text type for a .plainText request.
        DataRepresentation(exportedContentType: .plainText) { try await $0.payload() }
            .exportingCondition { $0.contentType == .plainText }
            .suggestedFileName { $0.fileName }
        DataRepresentation(exportedContentType: .json) { try await $0.payload() }
            .exportingCondition { $0.contentType == .json }
            .suggestedFileName { $0.fileName }
        DataRepresentation(exportedContentType: .commaSeparatedText) { try await $0.payload() }
            .exportingCondition { $0.contentType == .commaSeparatedText }
            .suggestedFileName { $0.fileName }
        DataRepresentation(contentType: .data) { item in
            try await item.payload()
        } importing: { data in
            ShareItem(data: data, fileName: "imported.json", contentType: .json)
        }
        .suggestedFileName { item in
            item.fileName
        }
    }

    public static var empty: ShareItem {
        .init(data: Data(), fileName: "empty", contentType: .data)
    }
}
