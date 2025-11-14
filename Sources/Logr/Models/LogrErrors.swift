//
//  LogrErrors.swift
//  Logr
//
//  Created by martin on 14/09/2025.
//

import Foundation

public enum LogRErrors: Error, LocalizedError {
    case invalidJSON
    case directoryNotFound
    case fileNotFound
    case encodingFailed
    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case .invalidJSON:
            "Invalid JSON format in configuration"
        case .fileNotFound:
            "Configuration file not found"
        case .encodingFailed:
            "Failed to encode configuration"
        case .decodingFailed:
            "Failed to decode configuration"
        case .directoryNotFound:
            "Directory not found"
        }
    }
}
