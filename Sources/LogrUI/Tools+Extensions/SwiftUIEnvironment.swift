//
//  SwiftUIEnvironment.swift
//  Logr
//
//  Created by martin on 13/11/2025.
//

import Logr
import LogrNetwork
import SwiftUI

// MARK: - Environment Key and Values

public extension EnvironmentValues {
    /// The logging service available to `LogrUI` views.
    ///
    /// Defaults to a no-op `DisabledLogR` so views render a safe, empty state
    /// when no logger has been injected. Provide a real service with
    /// ``SwiftUICore/View/logRService(_:)`` (or `.environment(\.logService, logger)`).
    @Entry var logService: any LogRService = DisabledLogR()

    /// The `NetworkLogger` whose captured bodies ``NetworkLogDetailView`` shows, and which ``LogViewer``'s
    /// Clear All Logs also clears. `nil` by default: details then show no bodies.
    @Entry var networkLogger: NetworkLogger?
}

public struct LogRServiceModifier: ViewModifier {
    let service: any LogRService

    public func body(content: Content) -> some View {
        content
            .environment(\.logService, service)
    }
}

public extension View {
    /// Injects a `LogRService` into the SwiftUI environment.
    func logRService(_ service: any LogRService) -> some View {
        modifier(LogRServiceModifier(service: service))
    }
}
