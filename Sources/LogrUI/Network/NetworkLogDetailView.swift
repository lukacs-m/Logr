//
//  NetworkLogDetailView.swift
//  LogrUI
//

import Logr
import LogrNetwork
import SwiftUI

/// One request `NetworkLogger` recorded: overview, phase timings, headers and captured bodies.
///
/// Bodies are loaded when the view appears, from the `NetworkLogger` in the environment
/// (`.environment(\.networkLogger, networkLogger)`); once pruned or cleared they read "Body no longer kept".
public struct NetworkLogDetailView: View {
    private let entry: LogEntry

    /// Shows `entry`, an entry `NetworkLogger` recorded.
    public init(entry: LogEntry) {
        self.entry = entry
    }

    public var body: some View {
        if let request = NetworkRequest(entry) {
            List {
                OverviewSection(request: request)
                TimingSection(request: request)
                HeadersSection(title: "Request Headers", headers: request.headers(HTTPLogFields.requestHeaders))
                HeadersSection(title: "Response Headers", headers: request.headers(HTTPLogFields.responseHeaders))
                if case let .string(bodyID)? = entry.metadata?[HTTPLogFields.bodyID] {
                    BodySection(bodyID: bodyID)
                }
            }
            .navigationTitle("\(request.method) \(request.path)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        } else {
            ContentUnavailableView("Not a Network Request", systemImage: "network.slash")
        }
    }
}

private struct OverviewSection: View {
    let request: NetworkRequest

    var body: some View {
        Section("Overview") {
            VStack(alignment: .leading, spacing: 4) {
                Text("URL")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(request.url)
                    .font(.callout.monospaced())
                    .selectableText()
            }
            .accessibilityElement(children: .combine)
            LabeledContent("Status") {
                StatusLabel(request: request)
            }
            if case let .string(error)? = request.entry.metadata?[HTTPLogFields.error] {
                LabeledContent("Error", value: error)
            }
            if let duration = request.durationText {
                LabeledContent("Duration", value: duration)
            }
            if let bytes = request.requestBytes {
                LabeledContent("Request size", value: NetworkRequest.bytes(bytes))
            }
            if let bytes = request.responseBytes {
                LabeledContent("Response size", value: NetworkRequest.bytes(bytes))
            }
            if case let .string(name)? = request.entry.metadata?[HTTPLogFields.networkProtocol] {
                LabeledContent("Protocol", value: name)
            }
            if case let .bool(reused)? = request.entry.metadata?[HTTPLogFields.reusedConnection] {
                LabeledContent("Reused connection") {
                    Text(reused ? "Yes" : "No")
                }
            }
            LabeledContent("Time", value: request.entry.timestamp.formatted(date: .abbreviated, time: .standard))
        }
    }
}

// MARK: - Timing

private struct TimingSection: View {
    let request: NetworkRequest

    private static let phases: [(key: String, title: LocalizedStringKey, tint: Color)] = [
        (HTTPLogFields.domainLookupMilliseconds, "DNS lookup", .teal),
        (HTTPLogFields.connectMilliseconds, "Connection", .orange),
        (HTTPLogFields.secureConnectionMilliseconds, "TLS handshake", .purple),
        (HTTPLogFields.requestMilliseconds, "Request sent", .green),
        (HTTPLogFields.waitMilliseconds, "Waiting for response", .indigo),
        (HTTPLogFields.responseMilliseconds, "Response received", .blue)
    ]

    var body: some View {
        let measured = Self.phases.compactMap { phase -> (LocalizedStringKey, Color, Double)? in
            guard case let .double(value)? = request.entry.metadata?[phase.key] else { return nil }
            return (phase.title, phase.tint, max(0, value))
        }
        // A waterfall of the phases alone: the task's duration also counts queueing and redirects.
        let total = max(measured.reduce(0) { $0 + $1.2 }, 0.001)
        if !measured.isEmpty {
            Section("Timing") {
                ForEach(measured.indices, id: \.self) { index in
                    let (title, tint, value) = measured[index]
                    let start = measured[..<index].reduce(0) { $0 + $1.2 }
                    TimingRow(title: title, tint: tint, milliseconds: value,
                              start: start / total, length: value / total)
                }
            }
        }
    }
}

private struct TimingRow: View {
    let title: LocalizedStringKey
    let tint: Color
    let milliseconds: Double
    let start: Double
    let length: Double
    @ScaledMetric private var barHeight = 6.0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let header = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        VStack(alignment: .leading, spacing: 6) {
            header {
                Text(title)
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 8)
                }
                Text(NetworkRequest.milliseconds(milliseconds))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                Capsule()
                    .fill(tint)
                    .frame(width: max(barHeight, geometry.size.width * length))
                    .offset(x: min(geometry.size.width * start, geometry.size.width - barHeight))
            }
            .frame(height: barHeight)
            .background(Capsule().fill(.quaternary))
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Headers

private struct HeadersSection: View {
    let title: LocalizedStringKey
    let headers: [(name: String, value: String)]?

    var body: some View {
        if let headers {
            Section(title) {
                if headers.isEmpty {
                    Text("None")
                        .foregroundStyle(.secondary)
                }
                ForEach(headers, id: \.name) { header in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(header.name)
                            .font(.subheadline.weight(.medium))
                        Text(header.value)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .selectableText()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

// MARK: - Bodies

private struct BodySection: View {
    let bodyID: String
    @Environment(\.networkLogger) private var networkLogger
    @State private var state = LoadState.loading

    enum LoadState {
        case loading
        case loaded(NetworkBody)
        case gone
        case failed(String)
        case unavailable
    }

    var body: some View {
        Section("Body") {
            switch state {
            case .loading:
                ProgressView()
            case let .loaded(body):
                if let data = body.request {
                    BodyLink(title: "Request body", data: data, isTruncated: body.isRequestTruncated)
                }
                if let data = body.response {
                    BodyLink(title: "Response body", data: data, isTruncated: body.isResponseTruncated)
                }
            case .gone:
                Text("Body no longer kept")
                    .foregroundStyle(.secondary)
            case let .failed(message):
                Text(message)
                    .foregroundStyle(.secondary)
            case .unavailable:
                Text("Put the NetworkLogger in the environment to show bodies.")
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: bodyID) {
            state = .loading
            guard let networkLogger else {
                state = .unavailable
                return
            }
            do {
                state = try await networkLogger.body(id: bodyID).map(LoadState.loaded) ?? .gone
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}

private struct BodyLink: View {
    let title: LocalizedStringKey
    let data: Data
    let isTruncated: Bool

    var body: some View {
        NavigationLink {
            NetworkBodyView(title: title, data: data, isTruncated: isTruncated)
        } label: {
            LabeledContent(title, value: NetworkRequest.bytes(data.count))
        }
    }
}

private struct NetworkBodyView: View {
    let title: LocalizedStringKey
    let data: Data
    let isTruncated: Bool

    var body: some View {
        // Formatted here, not in the link: a link builds its destination on every render of the list.
        let text = Self.text(of: data)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if isTruncated {
                    Label("Only the beginning of this body was kept.", systemImage: "scissors")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text(text)
                    .font(.callout.monospaced())
                    .selectableText()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                #if os(iOS) || os(macOS)
                Button("Copy", systemImage: "doc.on.doc") {
                    #if os(iOS)
                    UIPasteboard.general.string = text
                    #else
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    #endif
                }
                #endif
                #if !os(tvOS)
                ShareLink(item: text)
                #endif
            }
        }
    }

    /// JSON pretty-printed when it parses, anything else as UTF-8.
    static func text(of data: Data) -> String {
        // Kept text bodies were never depth-checked; the main thread's stack is smaller on watchOS.
        if !BodyKind.jsonNesting(of: data, exceeds: 128),
           let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
           let pretty = try? JSONSerialization.data(withJSONObject: object,
                                                    options: [
                                                        .prettyPrinted,
                                                        .sortedKeys,
                                                        .fragmentsAllowed,
                                                        .withoutEscapingSlashes
                                                    ]) {
            // Foundation prints an empty container across lines; a JSON string cannot hold a raw newline.
            return String(decoding: pretty, as: UTF8.self)
                .replacing(/\{\n\n\s*\}/, with: "{}")
                .replacing(/\[\n\n\s*\]/, with: "[]")
        }
        return String(decoding: data, as: UTF8.self)
    }
}

extension View {
    /// Text selection where the platform has it.
    func selectableText() -> some View {
        #if os(iOS) || os(macOS)
        textSelection(.enabled)
        #else
        self
        #endif
    }
}

#Preview {
    NavigationStack {
        if let entry = NetworkPreview.service().recentLogs
            .first(where: { $0.metadata?[HTTPLogFields.status] == 200 }) {
            NetworkLogDetailView(entry: entry)
        }
    }
}
