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
public struct ShareItem: Transferable {
    let data: Data
    public let fileName: String
    let contentType: UTType

    public init(data: Data, fileName: String, contentType: UTType) {
        self.data = data
        self.fileName = fileName
        self.contentType = contentType
    }

    public static var transferRepresentation: some TransferRepresentation {
        // CSV conforms to plain text; prefer the exact text type for a .plainText request.
        DataRepresentation(exportedContentType: .plainText) { $0.data }
            .exportingCondition { $0.contentType == .plainText }
            .suggestedFileName { $0.fileName }
        DataRepresentation(exportedContentType: .json) { $0.data }
            .exportingCondition { $0.contentType == .json }
            .suggestedFileName { $0.fileName }
        DataRepresentation(exportedContentType: .commaSeparatedText) { $0.data }
            .exportingCondition { $0.contentType == .commaSeparatedText }
            .suggestedFileName { $0.fileName }
        DataRepresentation(contentType: .data) { item in
            item.data
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
