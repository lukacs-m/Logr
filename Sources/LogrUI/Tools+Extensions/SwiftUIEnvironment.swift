//
//  SwiftUIEnvironment.swift
//  Logr
//
//  Created by martin on 13/11/2025.
//

import Logr
import SwiftUI

// MARK: - Environment Key and Values

public extension EnvironmentValues {
    #if DEBUG
    @Entry var logService: LogRService = MockLogR()
    #else
    @Entry var logService: LogRService = LogR()
    #endif
}

public struct LogRServiceModifier: ViewModifier {
    let service: LogRService

    public func body(content: Content) -> some View {
        content
            .environment(\.logService, service)
    }
}

public extension View {
    /// Injects a LogRService into the SwiftUI environment
    func logRService(_ service: LogRService) -> some View {
        modifier(LogRServiceModifier(service: service))
    }
}
