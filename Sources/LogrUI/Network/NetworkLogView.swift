//
//  NetworkLogView.swift
//  LogrUI
//

import Logr
import LogrNetwork
import SwiftUI

/// The requests `NetworkLogger` recorded in the environment's service, newest first.
///
/// Each row shows the method, path, host, status, duration and response size; a row opens
/// ``NetworkLogDetailView``. Search matches the URL, method and status; the toolbar filters by status class.
/// Host it in a `NavigationStack`. To show captured bodies, put the `NetworkLogger` in the environment with
/// `.environment(\.networkLogger, networkLogger)`.
///
/// ```swift
/// NavigationStack { NetworkLogView() }
///     .logRService(logger)
///     .environment(\.networkLogger, networkLogger)
/// ```
public struct NetworkLogView: View {
    @State private var searchText = ""
    @State private var query = ""
    @State private var statusFilter: HTTPStatusClass?

    public init() {}

    public var body: some View {
        NetworkRequestList(query: query, statusFilter: statusFilter)
            .navigationTitle("Network")
            .searchable(text: $searchText, prompt: "Search requests")
            .task(id: searchText) {
                // The list re-scans every cached entry when `query` changes: wait for typing to pause.
                if !searchText.isEmpty {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                }
                query = searchText
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    StatusFilterMenu(selection: $statusFilter)
                }
            }
    }
}

/// Its own view so that keystrokes, which only change `searchText` in the parent, do not re-scan the logs.
private struct NetworkRequestList: View {
    let query: String
    let statusFilter: HTTPStatusClass?
    @Environment(\.logService) private var logr

    var body: some View {
        let all = logr.recentLogs.compactMap(NetworkRequest.init)
        let requests = all.filter { matches($0) }
        List(requests) { request in
            NavigationLink {
                NetworkLogDetailView(entry: request.entry)
            } label: {
                NetworkRequestRow(request: request)
            }
        }
        .overlay {
            if all.isEmpty {
                ContentUnavailableView("No Requests", systemImage: "network",
                                       description: Text("Requests recorded with LogrNetwork appear here."))
            } else if requests.isEmpty {
                ContentUnavailableView("No Matching Requests", systemImage: "magnifyingglass",
                                       description: Text("Try another search or status filter."))
            }
        }
    }

    private func matches(_ request: NetworkRequest) -> Bool {
        if let statusFilter, request.statusClass != statusFilter {
            return false
        }
        guard !query.isEmpty else { return true }
        return request.url.localizedCaseInsensitiveContains(query)
            || request.method.localizedCaseInsensitiveContains(query)
            || request.statusText.localizedCaseInsensitiveContains(query)
    }
}

private struct StatusFilterMenu: View {
    @Binding var selection: HTTPStatusClass?

    var body: some View {
        LogActionsMenu {
            Picker("Status", selection: $selection) {
                Text("All statuses").tag(HTTPStatusClass?.none)
                ForEach(HTTPStatusClass.allCases) { statusClass in
                    Text(statusClass.title).tag(Optional(statusClass))
                }
            }
            #if !os(watchOS)
            .pickerStyle(.inline)
            #endif
        } label: {
            Label("Status", systemImage: selection == nil ? "line.3.horizontal.decrease.circle"
                : "line.3.horizontal.decrease.circle.fill")
        }
    }
}

struct NetworkRequestRow: View {
    let request: NetworkRequest
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        VStack(alignment: .leading, spacing: 4) {
            layout {
                HStack(alignment: .firstTextBaseline) {
                    Text(request.method)
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(request.path)
                        .lineLimit(2)
                }
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 8)
                }
                StatusLabel(request: request)
            }
            Text(details)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var details: String {
        var parts = [request.host]
        if let duration = request.durationText {
            parts.append(duration)
        }
        if let bytes = request.responseBytes {
            parts.append(NetworkRequest.bytes(bytes))
        }
        parts.append(request.entry.timestamp.formatted(date: .omitted, time: .standard))
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// The status as a coloured dot and text, so colour is never the only cue.
struct StatusLabel: View {
    let request: NetworkRequest
    @ScaledMetric private var dot = 8.0

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(request.statusClass.tint)
                .frame(width: dot, height: dot)
                .accessibilityHidden(true)
            Text(request.statusText)
                .font(.subheadline.monospacedDigit().weight(.semibold))
        }
        .fixedSize()
    }
}

#Preview {
    NavigationStack {
        NetworkLogView()
    }
    .environment(\.logService, NetworkPreview.service())
}
