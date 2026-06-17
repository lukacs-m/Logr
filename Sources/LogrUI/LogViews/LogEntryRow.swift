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
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .init(horizontal: .leading, vertical: .top))
                .foregroundStyle(.secondary)
            }
        } label: {
            mainRowContent
        }
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .init(horizontal: .leading, vertical: .top))
        .onChange(of: displayState) { _, newGlobalState in
            isExpanded = newGlobalState
        }
    }

    static func == (lhs: LogEntryRow, rhs: LogEntryRow) -> Bool {
        lhs.entry == rhs.entry && lhs.displayState == rhs.displayState
    }
}

private extension LogEntryRow {
    var mainRowContent: some View {
        Button {
                isExpanded.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    LogLevelBadge(level: entry.level)
                    Text(entry.category.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(entry.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .fontWeight(.semibold)
                Text(entry.message)
                    .fontWeight(.semibold)
                    .lineLimit(isExpanded ? nil : 3)
            }
            .contentShape(.rect)
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .init(horizontal: .leading, vertical: .top))
        }
        .buttonStyle(.plain)
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
        level.tint
    }

    private var foregroundColor: Color {
        .white
    }
}
