//
//  NetworkDemoSection.swift
//  LogRExample
//
//  Fires real requests through LogrNetwork's two capture paths.
//

import Foundation
import Logr
import LogrNetwork
import LogrUI
import SwiftUI

struct NetworkDemoSection: View {
    @Environment(\.networkLogger) private var networkLogger
    @State private var lastResult = ""

    var body: some View {
        Section {
            NetworkDemoButton(title: "GET with a token in the query", systemImage: "arrow.down.circle") {
                var request = URLRequest(url: URL(string: "https://httpbin.org/get?page=1&token=abc123")!)
                request.setValue("Bearer demo-secret", forHTTPHeaderField: "Authorization")
                return request
            } run: { await run($0) }
            NetworkDemoButton(title: "POST a JSON login", systemImage: "arrow.up.circle") {
                var request = URLRequest(url: URL(string: "https://httpbin.org/post")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = Data(#"{"username":"zoe","password":"hunter2"}"#.utf8)
                return request
            } run: { await run($0) }
            NetworkDemoButton(title: "404 Not Found", systemImage: "questionmark.circle") {
                URLRequest(url: URL(string: "https://httpbin.org/status/404")!)
            } run: { await run($0) }
            NetworkDemoButton(title: "500 Server Error", systemImage: "exclamationmark.octagon") {
                URLRequest(url: URL(string: "https://httpbin.org/status/500")!)
            } run: { await run($0) }
            NetworkDemoButton(title: "Unreachable host", systemImage: "wifi.slash") {
                URLRequest(url: URL(string: "https://logr-demo.invalid/ping")!)
            } run: { await run($0) }
            Button("Through a session delegate", systemImage: "arrow.triangle.branch") {
                runThroughProxy()
            }
            .disabled(networkLogger == nil)
            if !lastResult.isEmpty {
                Text(lastResult)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Network")
        } footer: {
            Text("Real requests to httpbin.org, recorded by LogrNetwork with bodies. Open the Network button in the Log Viewer.")
        }
    }

    private func run(_ request: URLRequest) async {
        guard let networkLogger else { return }
        do {
            let (_, response) = try await URLSession.shared.loggedData(for: request, to: networkLogger)
            lastResult = "Status \((response as? HTTPURLResponse)?.statusCode ?? 0)"
        } catch {
            lastResult = error.localizedDescription
        }
    }

    private func runThroughProxy() {
        guard let networkLogger else { return }
        let delegate = LogrURLSessionProxyDelegate(logger: networkLogger)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        session.dataTask(with: URL(string: "https://httpbin.org/json")!).resume()
        session.finishTasksAndInvalidate()
        lastResult = "Sent through LogrURLSessionProxyDelegate"
    }
}

private struct NetworkDemoButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let request: () -> URLRequest
    let run: (URLRequest) async -> Void
    @State private var isRunning = false

    var body: some View {
        Button {
            isRunning = true
            Task {
                await run(request())
                isRunning = false
            }
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                if isRunning {
                    ProgressView()
                }
            }
        }
        .disabled(isRunning)
    }
}
