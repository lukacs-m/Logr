//  
//  ExportFormat.swift
//  Logr
//
//  Created by martin on 19/11/2025.
//

import Foundation
import UniformTypeIdentifiers

public enum ExportFormat: CaseIterable, Identifiable {
    case json
    case csv
    case txt

   public var id: Self { self }
    
    public var fileExtension: String {
        switch self {
        case .json: "json"
        case .csv: "csv"
        case .txt: "txt"
        }
    }
    
    public var contentType: UTType {
        switch self {
            case .json: .json
        case .csv: .commaSeparatedText
        case .txt: .plainText
        }
    }
}
