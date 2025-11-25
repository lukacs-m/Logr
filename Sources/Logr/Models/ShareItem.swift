//
//  ShareItem.swift
//  Logr
//
//  Created by martin on 23/11/2025.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Share Item

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
