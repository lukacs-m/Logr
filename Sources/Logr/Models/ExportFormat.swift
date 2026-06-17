//
//  ExportFormat.swift
//  Logr
//
//  Created by martin on 19/11/2025.
//

import Foundation
import UniformTypeIdentifiers

public enum ExportFormat: CaseIterable, Identifiable, Sendable {
    /// Standard JSON format.
    case json
    /// Comma-separated values format.
    case csv
    /// Plain text format.
    case txt

    public var id: Self { self }

    /// The file extension for this format.
    public var fileExtension: String {
        switch self {
        case .json: "json"
        case .csv: "csv"
        case .txt: "txt"
        }
    }

    /// Human-readable format name.
    public var formatName: String {
        switch self {
        case .json: "JSON"
        case .csv: "CSV"
        case .txt: "Plain Text"
        }
    }

    /// The UTType content type for this format.
    public var contentType: UTType {
        switch self {
        case .json: .json
        case .csv: .commaSeparatedText
        case .txt: .plainText
        }
    }

    /// Description of the format and its use case.
    public var formatDescription: String {
        switch self {
        case .json: "Structured data format, preserves all fields"
        case .csv: "Spreadsheet compatible, good for analysis"
        case .txt: "Human readable format, easy to view"
        }
    }
}
