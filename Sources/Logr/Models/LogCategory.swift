//
//  LogCategory.swift
//  Logr
//
//  Created by martin on 02/11/2025.
//

import Foundation

/// Comprehensive category system for organizing and filtering logs.
///
/// `LogCategory` provides 47 predefined categories organized into logical groups,
/// plus support for custom project-specific categories.
///
/// ## Overview
///
/// Categories help organize logs by system area, making it easier to filter, search,
/// and analyze logs from specific parts of your application. Each category maps to
/// an OSLog category and is Codable for persistence.
///
/// ## Predefined Categories
///
/// The categories are organized into nine main groups:
///
/// **System & Core**: `.system`, `.lifecycle`, `.initialization`, `.configuration`
///
/// **Networking**: `.network`, `.api`, `.http`, `.websocket`, `.ssl`
///
/// **User Interface**: `.ui`, `.navigation`, `.animation`, `.layout`, `.gesture`
///
/// **Data & Storage**: `.database`, `.coreData`, `.fileSystem`, `.cache`, `.persistence`, `.sync`
///
/// **Security & Authentication**: `.authentication`, `.authorization`, `.security`, `.encryption`, `.keychain`, `.biometrics`
///
/// **Performance & Monitoring**: `.performance`, `.memory`, `.cpu`, `.battery`, `.analytics`, `.crash`, `.profiling`
///
/// **External Services**: `.push`, `.location`, `.camera`, `.microphone`, `.contacts`, `.calendar`, `.photos`
///
/// **Business Logic**: `.payment`, `.subscription`, `.purchase`, `.user`, `.content`, `.search`
///
/// **Development & Testing**: `.debug`, `.test`, `.mock`
///
/// ## Custom Categories
///
/// For project-specific needs, use `.custom(String)`:
///
/// ```swift
/// logger.info("Inventory updated", category: .custom("inventory"))
/// logger.debug("Feature flag toggled", category: .custom("feature-flags"))
/// ```
///
/// ## Usage Examples
///
/// ```swift
/// // Networking
/// logger.info("API request started", category: .network)
/// logger.error("Request failed", category: .api)
///
/// // UI Events
/// logger.debug("View appeared", category: .ui)
/// logger.info("Navigation completed", category: .navigation)
///
/// // Performance
/// logger.notice("Memory usage: 45MB", category: .performance)
/// logger.debug("CPU usage: 12%", category: .cpu)
///
/// // Security
/// logger.error("Authentication failed", category: .authentication)
/// logger.fault("Security breach detected", category: .security)
/// ```
///
/// ## Topics
///
/// ### System & Core
/// - ``system``
/// - ``lifecycle``
/// - ``initialization``
/// - ``configuration``
///
/// ### Networking
/// - ``network``
/// - ``api``
/// - ``http``
/// - ``websocket``
/// - ``ssl``
///
/// ### User Interface
/// - ``ui``
/// - ``navigation``
/// - ``animation``
/// - ``layout``
/// - ``gesture``
///
/// ### Data & Storage
/// - ``database``
/// - ``coreData``
/// - ``fileSystem``
/// - ``cache``
/// - ``persistence``
/// - ``sync``
///
/// ### Security & Authentication
/// - ``authentication``
/// - ``authorization``
/// - ``security``
/// - ``encryption``
/// - ``keychain``
/// - ``biometrics``
///
/// ### Performance & Monitoring
/// - ``performance``
/// - ``memory``
/// - ``cpu``
/// - ``battery``
/// - ``analytics``
/// - ``crash``
/// - ``profiling``
///
/// ### External Services
/// - ``push``
/// - ``location``
/// - ``camera``
/// - ``microphone``
/// - ``contacts``
/// - ``calendar``
/// - ``photos``
///
/// ### Business Logic
/// - ``payment``
/// - ``subscription``
/// - ``purchase``
/// - ``user``
/// - ``content``
/// - ``search``
///
/// ### Development & Testing
/// - ``debug``
/// - ``test``
/// - ``mock``
///
/// ### Custom
/// - ``custom(_:)``
///
/// ### Properties
/// - ``rawValue``
/// - ``displayName``
/// - ``common``
/// - ``predefined``
public enum LogCategory: Sendable, Codable, Hashable, Equatable {
    // MARK: - System & Core

    /// General system-level logs.
    case system
    /// App lifecycle events (launch, terminate, background, foreground).
    case lifecycle
    /// Initialization and setup operations.
    case initialization
    /// Configuration changes and updates.
    case configuration

    // MARK: - Networking

    /// General networking operations.
    case network
    /// API requests and responses.
    case api
    /// HTTP-specific operations.
    case http
    /// WebSocket connections and messages.
    case websocket
    /// SSL/TLS certificate and encryption issues.
    case ssl

    // MARK: - User Interface

    /// User interface events and updates.
    case ui
    /// Navigation and routing operations.
    case navigation
    /// Animation-related logs.
    case animation
    /// Layout calculations and constraints.
    case layout
    /// Gesture recognition and handling.
    case gesture

    // MARK: - Data & Storage

    /// Database operations (SQLite, Core Data, etc.).
    case database
    /// Core Data specific operations.
    case coreData
    /// File system read/write operations.
    case fileSystem
    /// Cache operations and management.
    case cache
    /// General persistence operations.
    case persistence
    /// Data synchronization operations.
    case sync

    // MARK: - Security & Authentication

    /// User authentication operations.
    case authentication
    /// Authorization and permissions.
    case authorization
    /// General security-related logs.
    case security
    /// Encryption and decryption operations.
    case encryption
    /// Keychain access and operations.
    case keychain
    /// Biometric authentication (Face ID, Touch ID).
    case biometrics

    // MARK: - Performance & Monitoring

    /// Performance measurements and benchmarks.
    case performance
    /// Memory usage and management.
    case memory
    /// CPU usage and profiling.
    case cpu
    /// Battery usage and power management.
    case battery
    /// Analytics tracking and reporting.
    case analytics
    /// Crash reports and diagnostics.
    case crash
    /// Performance profiling operations.
    case profiling

    // MARK: - External Services

    /// Push notification operations.
    case push
    /// Location services and tracking.
    case location
    /// Camera access and operations.
    case camera
    /// Microphone access and recording.
    case microphone
    /// Contacts access and operations.
    case contacts
    /// Calendar access and operations.
    case calendar
    /// Photo library access and operations.
    case photos

    // MARK: - Business Logic

    /// Payment processing operations.
    case payment
    /// Subscription management.
    case subscription
    /// In-app purchase operations.
    case purchase
    /// User account and profile operations.
    case user
    /// Content management operations.
    case content
    /// Search operations and indexing.
    case search

    // MARK: - Development & Testing

    /// Debug-specific logs for development.
    case debug
    /// Test execution and results.
    case test
    /// Mock data and services.
    case mock

    // MARK: - Custom

    /// Custom category for project-specific needs.
    ///
    /// Use this for specialized categories unique to your project:
    ///
    /// ```swift
    /// logger.info("Inventory updated", category: .custom("inventory"))
    /// ```
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
