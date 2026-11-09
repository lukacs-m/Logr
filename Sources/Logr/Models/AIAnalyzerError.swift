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
    /// The system throttled the model, as it does for apps in the background.
    case rateLimited
    case systemError(any Error)
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
        case .rateLimited:
            "Apple Intelligence is busy or the app is in the background. Please try again later."
        case let .systemError(error):
            "System error: \(error.localizedDescription)"
        case .missingAnalyzer:
            "No analyzer is configured for this app."
        }
    }
}
