//
//  LogEntryRow.swift
//  Logr
//
//  Created by Martin Lukacs on 17/11/2025.
//

import Logr
import SwiftUI

struct LogEntryRow: View, @MainActor Equatable {
    let entry: LogEntry
    @Binding var displayState: Bool
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                VStack(spacing: 5) {
                    DetailRow("File", URL(fileURLWithPath: entry.file).lastPathComponent)
                    DetailRow("Function", entry.function)
                    DetailRow("Line", "\(entry.line)")
                    DetailRow("Timestamp", entry.timestamp.formatted(.iso8601))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } label: {
            mainRowContent
        }
        .onChange(of: displayState) { _, newGlobalState in
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded = newGlobalState
            }
        }
//        .disclosureGroupStyle(CustomDisclosureGroupStyle(button: Text("ok")))
    }
    
    static func == (lhs: LogEntryRow, rhs: LogEntryRow) -> Bool {
        lhs.displayState == rhs.displayState && lhs.entry == rhs.entry && lhs.isExpanded == rhs.isExpanded
    }
}

private extension LogEntryRow {
    var mainRowContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                LogLevelBadge(level: entry.level)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.category.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(entry.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(entry.message)
                        .fontWeight(.semibold)
                        .lineLimit(isExpanded ? nil : 3)
                }

                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }
        }
    }
}

private struct DetailRow: View {
    private let label: String
    private let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text("\(label):")
                .fontWeight(.medium)
            Text(value)
            Spacer()
        }
    }
}

struct LogLevelBadge: View {
    let level: LogLevel

    var body: some View {
        Text(level.displayName.uppercased())
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch level {
        case .debug: .gray
        case .info: .blue
        case .notice: .green
        case .error: .orange
        case .fault: .red
        case .warning: .yellow
        }
    }

    private var foregroundColor: Color {
        .white
    }
}

// struct CustomDisclosureGroupStyle<Label: View>: DisclosureGroupStyle {
//    let button: Label
//
//    func makeBody(configuration: Configuration) -> some View {
//        HStack {
//            configuration.label
//            Spacer()
//            button
//                .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
//        }
//        .contentShape(Rectangle())
//        .onTapGesture {
//            withAnimation {
//                configuration.isExpanded.toggle()
//            }
//        }
//        if configuration.isExpanded {
//            configuration.content
//                .padding(.leading, 30)
//                .disclosureGroupStyle(self)
//        }
//    }
// }
