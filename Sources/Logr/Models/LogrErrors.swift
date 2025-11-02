//  
//  LogRErrors.swift
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
            return "Invalid JSON format in configuration"
        case .fileNotFound:
            return "Configuration file not found"
        case .encodingFailed:
            return "Failed to encode configuration"
        case .decodingFailed:
            return "Failed to decode configuration"
        case .directoryNotFound:
            return "Directory not found"
        }
    }
}
