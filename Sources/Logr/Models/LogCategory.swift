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
        case .system: return "system"
        case .lifecycle: return "lifecycle"
        case .initialization: return "initialization"
        case .configuration: return "configuration"
        case .network: return "network"
        case .api: return "api"
        case .http: return "http"
        case .websocket: return "websocket"
        case .ssl: return "ssl"
        case .ui: return "ui"
        case .navigation: return "navigation"
        case .animation: return "animation"
        case .layout: return "layout"
        case .gesture: return "gesture"
        case .database: return "database"
        case .coreData: return "coreData"
        case .fileSystem: return "fileSystem"
        case .cache: return "cache"
        case .persistence: return "persistence"
        case .sync: return "sync"
        case .authentication: return "authentication"
        case .authorization: return "authorization"
        case .security: return "security"
        case .encryption: return "encryption"
        case .keychain: return "keychain"
        case .biometrics: return "biometrics"
        case .performance: return "performance"
        case .memory: return "memory"
        case .cpu: return "cpu"
        case .battery: return "battery"
        case .analytics: return "analytics"
        case .crash: return "crash"
        case .profiling: return "profiling"
        case .push: return "push"
        case .location: return "location"
        case .camera: return "camera"
        case .microphone: return "microphone"
        case .contacts: return "contacts"
        case .calendar: return "calendar"
        case .photos: return "photos"
        case .payment: return "payment"
        case .subscription: return "subscription"
        case .purchase: return "purchase"
        case .user: return "user"
        case .content: return "content"
        case .search: return "search"
        case .debug: return "debug"
        case .test: return "test"
        case .mock: return "mock"
        case .custom(let value): return value
        }
    }
    
    public var displayName: String {
        switch self {
        case .system: return "System"
        case .lifecycle: return "Lifecycle"
        case .initialization: return "Initialization"
        case .configuration: return "Configuration"
        case .network: return "Network"
        case .api: return "API"
        case .http: return "HTTP"
        case .websocket: return "WebSocket"
        case .ssl: return "SSL/TLS"
        case .ui: return "User Interface"
        case .navigation: return "Navigation"
        case .animation: return "Animation"
        case .layout: return "Layout"
        case .gesture: return "Gesture"
        case .database: return "Database"
        case .coreData: return "Core Data"
        case .fileSystem: return "File System"
        case .cache: return "Cache"
        case .persistence: return "Persistence"
        case .sync: return "Synchronization"
        case .authentication: return "Authentication"
        case .authorization: return "Authorization"
        case .security: return "Security"
        case .encryption: return "Encryption"
        case .keychain: return "Keychain"
        case .biometrics: return "Biometrics"
        case .performance: return "Performance"
        case .memory: return "Memory"
        case .cpu: return "CPU"
        case .battery: return "Battery"
        case .analytics: return "Analytics"
        case .crash: return "Crash"
        case .profiling: return "Profiling"
        case .push: return "Push Notifications"
        case .location: return "Location"
        case .camera: return "Camera"
        case .microphone: return "Microphone"
        case .contacts: return "Contacts"
        case .calendar: return "Calendar"
        case .photos: return "Photos"
        case .payment: return "Payment"
        case .subscription: return "Subscription"
        case .purchase: return "Purchase"
        case .user: return "User"
        case .content: return "Content"
        case .search: return "Search"
        case .debug: return "Debug"
        case .test: return "Test"
        case .mock: return "Mock"
        case .custom(let value): return value.capitalized
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
        return predefined
    }
}

extension LogCategory: CustomStringConvertible {
    public var description: String {
        return displayName
    }
}