//
//  LogCategory.swift
//  Logr
//
//  Created by martin on 02/11/2025.
//

import Foundation

/// Comprehensive category system for organizing and filtering logs.
///
/// `LogCategory` provides 49 predefined categories organized into logical groups, and apps add their own
/// names.
///
/// ## Overview
///
/// Categories help organize logs by system area, making it easier to filter, search,
/// and analyze logs from specific parts of your application. Each category maps to
/// an OSLog category (its ``rawValue``) and encodes as that string.
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
/// **Security & Authentication**: `.authentication`, `.authorization`, `.security`, `.encryption`, `.keychain`,
/// `.biometrics`
///
/// **Performance & Monitoring**: `.performance`, `.memory`, `.cpu`, `.battery`, `.analytics`, `.crash`,
/// `.profiling`
///
/// **External Services**: `.push`, `.location`, `.camera`, `.microphone`, `.contacts`, `.calendar`, `.photos`
///
/// **Business Logic**: `.payment`, `.subscription`, `.purchase`, `.user`, `.content`, `.search`
///
/// **Development & Testing**: `.debug`, `.test`, `.mock`
///
/// ## Custom Categories
///
/// Add project-specific names in an extension, or pass a string literal; they display as written:
///
/// ```swift
/// extension LogCategory {
///     static let checkout: Self = "checkout"
/// }
///
/// logger.info("Order placed", category: .checkout)
/// logger.debug("Feature flag toggled", category: "feature-flags")
/// ```
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
/// ### Creating Categories
/// - ``init(rawValue:)``
/// - ``init(stringLiteral:)``
///
/// ### Properties
/// - ``rawValue``
/// - ``displayName``
/// - ``common``
/// - ``predefined``
public struct LogCategory: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral,
    CustomStringConvertible {
    /// The category's name, also used as the OSLog category.
    public let rawValue: String

    /// Creates the category named `rawValue`; a predefined name gives the predefined category.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Creates the category named by the literal, as in `category: "checkout"`.
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    // MARK: - System & Core

    /// General system-level logs.
    public static let system: Self = "system"
    /// App lifecycle events (launch, terminate, background, foreground).
    public static let lifecycle: Self = "lifecycle"
    /// Initialization and setup operations.
    public static let initialization: Self = "initialization"
    /// Configuration changes and updates.
    public static let configuration: Self = "configuration"

    // MARK: - Networking

    /// General networking operations.
    public static let network: Self = "network"
    /// API requests and responses.
    public static let api: Self = "api"
    /// HTTP-specific operations.
    public static let http: Self = "http"
    /// WebSocket connections and messages.
    public static let websocket: Self = "websocket"
    /// SSL/TLS certificate and encryption issues.
    public static let ssl: Self = "ssl"

    // MARK: - User Interface

    /// User interface events and updates.
    public static let ui: Self = "ui"
    /// Navigation and routing operations.
    public static let navigation: Self = "navigation"
    /// Animation-related logs.
    public static let animation: Self = "animation"
    /// Layout calculations and constraints.
    public static let layout: Self = "layout"
    /// Gesture recognition and handling.
    public static let gesture: Self = "gesture"

    // MARK: - Data & Storage

    /// Database operations (SQLite, Core Data, etc.).
    public static let database: Self = "database"
    /// Core Data specific operations.
    public static let coreData: Self = "coreData"
    /// File system read/write operations.
    public static let fileSystem: Self = "fileSystem"
    /// Cache operations and management.
    public static let cache: Self = "cache"
    /// General persistence operations.
    public static let persistence: Self = "persistence"
    /// Data synchronization operations.
    public static let sync: Self = "sync"

    // MARK: - Security & Authentication

    /// User authentication operations.
    public static let authentication: Self = "authentication"
    /// Authorization and permissions.
    public static let authorization: Self = "authorization"
    /// General security-related logs.
    public static let security: Self = "security"
    /// Encryption and decryption operations.
    public static let encryption: Self = "encryption"
    /// Keychain access and operations.
    public static let keychain: Self = "keychain"
    /// Biometric authentication (Face ID, Touch ID).
    public static let biometrics: Self = "biometrics"

    // MARK: - Performance & Monitoring

    /// Performance measurements and benchmarks.
    public static let performance: Self = "performance"
    /// Memory usage and management.
    public static let memory: Self = "memory"
    /// CPU usage and profiling.
    public static let cpu: Self = "cpu"
    /// Battery usage and power management.
    public static let battery: Self = "battery"
    /// Analytics tracking and reporting.
    public static let analytics: Self = "analytics"
    /// Crash reports and diagnostics.
    public static let crash: Self = "crash"
    /// Performance profiling operations.
    public static let profiling: Self = "profiling"

    // MARK: - External Services

    /// Push notification operations.
    public static let push: Self = "push"
    /// Location services and tracking.
    public static let location: Self = "location"
    /// Camera access and operations.
    public static let camera: Self = "camera"
    /// Microphone access and recording.
    public static let microphone: Self = "microphone"
    /// Contacts access and operations.
    public static let contacts: Self = "contacts"
    /// Calendar access and operations.
    public static let calendar: Self = "calendar"
    /// Photo library access and operations.
    public static let photos: Self = "photos"

    // MARK: - Business Logic

    /// Payment processing operations.
    public static let payment: Self = "payment"
    /// Subscription management.
    public static let subscription: Self = "subscription"
    /// In-app purchase operations.
    public static let purchase: Self = "purchase"
    /// User account and profile operations.
    public static let user: Self = "user"
    /// Content management operations.
    public static let content: Self = "content"
    /// Search operations and indexing.
    public static let search: Self = "search"

    // MARK: - Development & Testing

    /// Debug-specific logs for development.
    public static let debug: Self = "debug"
    /// Test execution and results.
    public static let test: Self = "test"
    /// Mock data and services.
    public static let mock: Self = "mock"

    /// A readable name: the curated one for predefined categories, the raw value for any other.
    public var displayName: String {
        Self.displayNames[rawValue] ?? rawValue
    }

    public var description: String {
        displayName
    }

    private static let displayNames: [String: String] = [
        "system": "System",
        "lifecycle": "Lifecycle",
        "initialization": "Initialization",
        "configuration": "Configuration",
        "network": "Network",
        "api": "API",
        "http": "HTTP",
        "websocket": "WebSocket",
        "ssl": "SSL/TLS",
        "ui": "User Interface",
        "navigation": "Navigation",
        "animation": "Animation",
        "layout": "Layout",
        "gesture": "Gesture",
        "database": "Database",
        "coreData": "Core Data",
        "fileSystem": "File System",
        "cache": "Cache",
        "persistence": "Persistence",
        "sync": "Synchronization",
        "authentication": "Authentication",
        "authorization": "Authorization",
        "security": "Security",
        "encryption": "Encryption",
        "keychain": "Keychain",
        "biometrics": "Biometrics",
        "performance": "Performance",
        "memory": "Memory",
        "cpu": "CPU",
        "battery": "Battery",
        "analytics": "Analytics",
        "crash": "Crash",
        "profiling": "Profiling",
        "push": "Push Notifications",
        "location": "Location",
        "camera": "Camera",
        "microphone": "Microphone",
        "contacts": "Contacts",
        "calendar": "Calendar",
        "photos": "Photos",
        "payment": "Payment",
        "subscription": "Subscription",
        "purchase": "Purchase",
        "user": "User",
        "content": "Content",
        "search": "Search",
        "debug": "Debug",
        "test": "Test",
        "mock": "Mock"
    ]

    /// Common categories for quick access
    public static let common: [LogCategory] = [
        .system, .network, .ui, .authentication, .database, .performance, .debug
    ]

    /// All predefined categories
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
}

// MARK: - Codable

public extension LogCategory {
    /// Decodes a category name. Also accepts the form Logr 1.x wrote, when `LogCategory` was an enum:
    /// `{"network":{}}` and `{"custom":{"_0":"Checkout"}}`.
    init(from decoder: any Decoder) throws {
        if let name = try? decoder.singleValueContainer().decode(String.self) {
            self.init(rawValue: name)
            return
        }
        let container = try decoder.container(keyedBy: LegacyKey.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Expected a category name"))
        }
        guard key.stringValue == "custom" else {
            self.init(rawValue: key.stringValue)
            return
        }
        let associatedValues = try container.nestedContainer(keyedBy: LegacyKey.self, forKey: key)
        try self.init(rawValue: associatedValues.decode(String.self, forKey: LegacyKey(stringValue: "_0")))
    }

    /// Encodes the category as its ``rawValue``.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

private struct LegacyKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        nil
    }
}

extension LogCategory: Identifiable {
    public var id: String {
        rawValue
    }
}

extension LogCategory: CaseIterable {
    public static var allCases: [LogCategory] {
        predefined
    }
}
