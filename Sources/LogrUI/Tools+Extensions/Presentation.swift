//
//  Presentation.swift
//  Logr
//
//  The single source of truth for how domain values are *styled* across Logr UI.
//

import Logr
import SwiftUI

// MARK: - LogLevel presentation

public extension LogLevel {
    /// The accent color for this level — the one place level colors are defined.
    ///
    /// Severity *ordering* stays in the domain (``LogLevel/priority``); only the visual style lives
    /// here. Every view resolves a level's color through this property rather than defining its own
    /// `switch`, so the same level can never render as a different color on different screens.
    var tint: Color {
        switch self {
        case .debug: .gray
        case .info: .blue
        case .notice: .cyan
        case .warning: .orange
        case .error: .red
        case .fault: .purple
        }
    }
}

// MARK: - LogSeverity presentation (AI analysis, iOS 26+)

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 12.0, *)
public extension LogSeverity {
    /// The accent color for this severity — the one place severity colors are defined.
    var tint: Color {
        switch self {
        case .critical: .red
        case .high: .orange
        case .medium: .yellow
        case .low: .blue
        }
    }

    /// The SF Symbol representing this severity — the one place severity symbols are defined.
    var symbolName: String {
        switch self {
        case .critical: "exclamationmark.triangle.fill"
        case .high: "exclamationmark.circle.fill"
        case .medium: "exclamationmark.circle"
        case .low: "info.circle"
        }
    }
}
