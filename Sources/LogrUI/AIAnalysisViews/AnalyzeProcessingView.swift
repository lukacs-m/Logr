//
//  AnalyzeProcessingView.swift
//  Logr
//
//  Created by martin on 29/11/2025.
//

import Logr
import SwiftUI

struct AnalyzeProcessingView: View {
    @Environment(\.logService) private var logr

    private var progress: AnalysisProgress? {
        logr.analysisProgress
    }

    var body: some View {
        VStack(spacing: 24) {
            progressIndicator

            VStack(spacing: 8) {
                Text("Analyzing Logs")
                    .font(.title3)
                    .fontWeight(.semibold)

                if let progress {
                    Text("\(progress.analyzedGroups) of \(progress.totalGroups) issues explained")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())

                    Text("\(progress.percentComplete)%")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .contentTransition(.numericText())
                } else {
                    Text("Apple Intelligence is reading your logs…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    @ViewBuilder
    private var progressIndicator: some View {
        if let progress {
            ProgressView(value: progress.progress)
                .progressViewStyle(.circular)
                .scaleEffect(1.5)
        } else {
            ProgressView()
                .scaleEffect(1.5)
        }
    }
}
