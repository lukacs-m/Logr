//
//  LogRPersistence.swift
//  Logr
//
//  Created by martin on 02/11/2025.
//

import Foundation

public enum AIAnalyzerError: Error, LocalizedError, Sendable {
    case modelUnavailable
    case contextLengthExceeded
    case inferenceTimeout
    case invalidResponse
    case noLogsToAnalyze
    case systemError(Error)

    public var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            "Apple Intelligence is not available on this device. Requires iOS 18+, macOS 15+, or later."
        case .contextLengthExceeded:
            "Too many logs to analyze in a single request. Try analyzing fewer logs."
        case .inferenceTimeout:
            "Analysis timed out. Please try again with fewer logs."
        case .invalidResponse:
            "Received an invalid response from the AI model."
        case .noLogsToAnalyze:
            "No logs available to analyze."
        case let .systemError(error):
            "System error: \(error.localizedDescription)"
        }
    }
}
