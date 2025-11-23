//
//  AIAnalyzerError.swift
//  Logr
//
//  Created by martin on 02/11/2025.
//

import Foundation

public enum AIAnalyzerError: Error, LocalizedError, Sendable {
    case modelUnavailable(String)
    case contextLengthExceeded
    case inferenceTimeout
    case invalidResponse
    case noLogsToAnalyze
    case systemError(Error)
    case mergeError
    case missingAnalyzer

    public var errorDescription: String? {
        switch self {
        case let .modelUnavailable(reason):
            "Apple Intelligence is not available on this device. \(reason)"
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
        case .mergeError:
            "Something went wrong while merging the analysis results. Please try again."
        case .missingAnalyzer:
            "No analyzer is configured for this app."
        }
    }
}
