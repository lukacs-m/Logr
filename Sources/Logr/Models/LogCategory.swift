import Foundation

public enum LogCategory: Sendable, Codable, Hashable {
    // System & Core
    case system
    case lifecycle
    case initialization
    case configuration

    // Networking
    case network
    case api
    case http
    case websocket
    case ssl

    // User Interface
    case ui
    case navigation
    case animation
    case layout
    case gesture

    // Data & Storage
    case database
    case coreData
    case fileSystem
    case cache
    case persistence
    case sync

    // Security & Authentication
    case authentication
    case authorization
    case security
    case encryption
    case keychain
    case biometrics

    // Performance & Monitoring
    case performance
    case memory
    case cpu
    case battery
    case analytics
    case crash
    case profiling

    // External Services
    case push
    case location
    case camera
    case microphone
    case contacts
    case calendar
    case photos

    // Business Logic
    case payment
    case subscription
    case purchase
    case user
    case content
    case search

    // Development & Testing
    case debug
    case test
    case mock

    // Custom category for project-specific needs
    case custom(String)

    public var rawValue: String {
        switch self {
        case .system: "system"
        case .lifecycle: "lifecycle"
        case .initialization: "initialization"
        case .configuration: "configuration"
        case .network: "network"
        case .api: "api"
        case .http: "http"
        case .websocket: "websocket"
        case .ssl: "ssl"
        case .ui: "ui"
        case .navigation: "navigation"
        case .animation: "animation"
        case .layout: "layout"
        case .gesture: "gesture"
        case .database: "database"
        case .coreData: "coreData"
        case .fileSystem: "fileSystem"
        case .cache: "cache"
        case .persistence: "persistence"
        case .sync: "sync"
        case .authentication: "authentication"
        case .authorization: "authorization"
        case .security: "security"
        case .encryption: "encryption"
        case .keychain: "keychain"
        case .biometrics: "biometrics"
        case .performance: "performance"
        case .memory: "memory"
        case .cpu: "cpu"
        case .battery: "battery"
        case .analytics: "analytics"
        case .crash: "crash"
        case .profiling: "profiling"
        case .push: "push"
        case .location: "location"
        case .camera: "camera"
        case .microphone: "microphone"
        case .contacts: "contacts"
        case .calendar: "calendar"
        case .photos: "photos"
        case .payment: "payment"
        case .subscription: "subscription"
        case .purchase: "purchase"
        case .user: "user"
        case .content: "content"
        case .search: "search"
        case .debug: "debug"
        case .test: "test"
        case .mock: "mock"
        case let .custom(value): value
        }
    }

    public var displayName: String {
        switch self {
        case .system: "System"
        case .lifecycle: "Lifecycle"
        case .initialization: "Initialization"
        case .configuration: "Configuration"
        case .network: "Network"
        case .api: "API"
        case .http: "HTTP"
        case .websocket: "WebSocket"
        case .ssl: "SSL/TLS"
        case .ui: "User Interface"
        case .navigation: "Navigation"
        case .animation: "Animation"
        case .layout: "Layout"
        case .gesture: "Gesture"
        case .database: "Database"
        case .coreData: "Core Data"
        case .fileSystem: "File System"
        case .cache: "Cache"
        case .persistence: "Persistence"
        case .sync: "Synchronization"
        case .authentication: "Authentication"
        case .authorization: "Authorization"
        case .security: "Security"
        case .encryption: "Encryption"
        case .keychain: "Keychain"
        case .biometrics: "Biometrics"
        case .performance: "Performance"
        case .memory: "Memory"
        case .cpu: "CPU"
        case .battery: "Battery"
        case .analytics: "Analytics"
        case .crash: "Crash"
        case .profiling: "Profiling"
        case .push: "Push Notifications"
        case .location: "Location"
        case .camera: "Camera"
        case .microphone: "Microphone"
        case .contacts: "Contacts"
        case .calendar: "Calendar"
        case .photos: "Photos"
        case .payment: "Payment"
        case .subscription: "Subscription"
        case .purchase: "Purchase"
        case .user: "User"
        case .content: "Content"
        case .search: "Search"
        case .debug: "Debug"
        case .test: "Test"
        case .mock: "Mock"
        case let .custom(value): value.capitalized
        }
    }

    /// Common categories for quick access
    public static let common: [LogCategory] = [
        .system, .network, .ui, .authentication, .database, .performance, .debug
    ]

    /// All predefined categories (excluding custom)
    public static let predefined: [LogCategory] = [
        .system, .lifecycle, .initialization, .configuration,
        .network, .api, .http, .websocket, .ssl,
        .ui, .navigation, .animation, .layout, .gesture,
        .database, .coreData, .fileSystem, .cache, .persistence, .sync,
        .authentication, .authorization, .security, .encryption, .keychain, .biometrics,
        .performance, .memory, .cpu, .battery, .analytics, .crash, .profiling,
        .push, .location, .camera, .microphone, .contacts, .calendar, .photos,
        .payment, .subscription, .purchase, .user, .content, .search,
        .debug, .test, .mock
    ]

    public init(rawValue: String) {
        if let predefined = Self.predefined.first(where: { $0.rawValue == rawValue }) {
            self = predefined
        } else {
            self = .custom(rawValue)
        }
    }
}

extension LogCategory: Identifiable {
    public var id: String { rawValue }
}

extension LogCategory: CaseIterable {
    public static var allCases: [LogCategory] {
        predefined
    }
}

extension LogCategory: CustomStringConvertible {
    public var description: String {
        displayName
    }
}
