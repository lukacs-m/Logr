//
//  MockDataGenerator.swift
//  LogRExample
//
//  Generates thousands of mock logs with realistic patterns, privacy issues, and error scenarios.
//

import Foundation
import Logr

// Helper to log with level and category using convenience methods
private func logMessage(logger: LogRService, level: LogLevel, message: String, category: LogCategory) {
    switch level {
    case .debug: logger.debug(message, category: category)
    case .info: logger.info(message, category: category)
    case .notice: logger.notice(message, category: category)
    case .warning: logger.warning(message, category: category)
    case .error: logger.error(message, category: category)
    case .fault: logger.fault(message, category: category)
    }
}

enum MockDataGenerator {
    // MARK: - Configuration

    private static let networkEndpoints = [
        "/api/v1/users", "/api/v1/products", "/api/v1/orders",
        "/api/v1/auth/login", "/api/v1/auth/refresh", "/api/v1/payments",
        "/api/v2/search", "/api/v2/recommendations", "/api/v2/analytics"
    ]

    private static let httpMethods = ["GET", "POST", "PUT", "DELETE", "PATCH"]
    private static let httpStatusCodes = [200, 201, 204, 400, 401, 403, 404, 500, 502, 503]

    private static let viewNames = [
        "HomeView", "ProfileView", "SettingsView", "CartView", "CheckoutView",
        "ProductDetailView", "SearchResultsView", "OrderHistoryView", "NotificationsView"
    ]

    private static let userActions = [
        "tapped button", "scrolled list", "swiped card", "pulled to refresh",
        "selected item", "dismissed modal", "changed tab", "submitted form"
    ]

    // MARK: - Privacy Issue Data (Demo purposes)

    private static let mockEmails = [
        "john.doe@example.com", "jane.smith@testmail.org",
        "user123@company.net", "support@demo.io"
    ]

    private static let mockPhoneNumbers = [
        "+1-555-123-4567", "1-800-555-0199", "(555) 987-6543"
    ]

    private static let mockTokens = [
        "sk_live_abc123xyz789def456",
        "api_key_prod_qwerty12345",
        "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.demo"
    ]

    private static let mockIPs = [
        "192.168.1.100", "10.0.0.50", "172.16.0.1"
    ]

    private static let mockSSNs = ["123-45-6789", "987-65-4321"]
    private static let mockCreditCards = ["4111-1111-1111-1111", "5500-0000-0000-0004"]

    // MARK: - Error Patterns

    private static let recurringErrors = [
        ("Network timeout connecting to payment service", LogCategory.network),
        ("Database connection pool exhausted", LogCategory.database),
        ("Authentication token expired", LogCategory.authentication),
        ("Memory pressure warning triggered", LogCategory.memory),
        ("Rate limit exceeded for API endpoint", LogCategory.api)
    ]

    private static let errorMessages = [
        "Connection refused", "Request timed out after 30s",
        "Invalid response format", "Certificate validation failed",
        "Resource not found", "Permission denied", "Quota exceeded"
    ]

    // MARK: - Main Generation Methods

    static func generateComprehensiveLogs(logger: LogRService,
                                          count: Int = 2_000,
                                          privacyIssues: Int = 25,
                                          errorPatterns: Int = 50) async {
        logger.info("Starting mock data generation: \(count) logs", category: .debug)

        await generateNormalOperationLogs(logger: logger, count: count - privacyIssues - errorPatterns)
        await generatePrivacyIssueLogs(logger: logger, count: privacyIssues)
        await generateErrorPatternLogs(logger: logger, count: errorPatterns)
        await generateAppLifecycleLogs(logger: logger)

        logger.notice("Mock data generation completed", category: .debug)
    }

    // MARK: - Normal Operation Logs

    private static func generateNormalOperationLogs(logger: LogRService, count: Int) async {
        let levels: [(LogLevel, Int)] = [
            (.debug, 40),
            (.info, 35),
            (.notice, 15),
            (.warning, 8),
            (.error, 2)
        ]

        for i in 0..<count {
            let level = weightedRandomLevel(levels)
            let (message, category) = generateNormalLogContent(index: i)
            logMessage(logger: logger, level: level, message: message, category: category)

            if i % 500 == 0, i > 0 {
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    private static func generateNormalLogContent(index: Int) -> (String, LogCategory) {
        let scenario = index % 10

        switch scenario {
        case 0, 1: // Network
            return generateNetworkLog()
        case 2, 3: // UI
            return generateUILog()
        case 4: // Database
            return generateDatabaseLog()
        case 5: // Cache
            return generateCacheLog()
        case 6: // Performance
            return generatePerformanceLog()
        case 7: // Authentication
            return generateAuthLog()
        case 8: // System
            return generateSystemLog()
        default: // Misc
            return generateMiscLog()
        }
    }

    private static func generateNetworkLog() -> (String, LogCategory) {
        let endpoint = networkEndpoints.randomElement()!
        let method = httpMethods.randomElement()!
        let status = httpStatusCodes.filter { $0 < 400 }.randomElement()!
        let latency = Int.random(in: 20...500)

        return ("\(method) \(endpoint) completed: \(status) (\(latency)ms)", .http)
    }

    private static func generateUILog() -> (String, LogCategory) {
        let view = viewNames.randomElement()!
        let action = userActions.randomElement()!

        return ("User \(action) in \(view)", .ui)
    }

    private static func generateDatabaseLog() -> (String, LogCategory) {
        let operations = ["SELECT", "INSERT", "UPDATE", "DELETE"]
        let tables = ["users", "products", "orders", "sessions", "preferences"]
        let op = operations.randomElement()!
        let table = tables.randomElement()!
        let rows = Int.random(in: 1...100)

        return ("\(op) on \(table): \(rows) rows affected (\(Int.random(in: 1...50))ms)", .database)
    }

    private static func generateCacheLog() -> (String, LogCategory) {
        let hit = Bool.random()
        let key = "cache_key_\(Int.random(in: 1_000...9_999))"

        return ("Cache \(hit ? "HIT" : "MISS"): \(key)", .cache)
    }

    private static func generatePerformanceLog() -> (String, LogCategory) {
        let metrics = [
            "Frame time: \(Int.random(in: 8...33))ms",
            "Memory usage: \(Int.random(in: 100...400))MB",
            "CPU: \(Int.random(in: 5...80))%",
            "Battery drain rate: \(Double.random(in: 0.5...3.0).formatted(.number.precision(.fractionLength(1))))%/hr"
        ]

        return (metrics.randomElement()!, .performance)
    }

    private static func generateAuthLog() -> (String, LogCategory) {
        let events = [
            "Session validated successfully",
            "Token refresh initiated",
            "Biometric check passed",
            "User permissions loaded",
            "Session extended for 24h"
        ]

        return (events.randomElement()!, .authentication)
    }

    private static func generateSystemLog() -> (String, LogCategory) {
        let events = [
            "Background task scheduled",
            "Push notification registered",
            "App state changed to active",
            "Device orientation changed",
            "System memory available: \(Int.random(in: 500...2_000))MB"
        ]

        return (events.randomElement()!, .system)
    }

    private static func generateMiscLog() -> (String, LogCategory) {
        let categories: [LogCategory] = [.analytics, .push, .sync, .search]
        let messages = [
            "Analytics event tracked",
            "Sync completed successfully",
            "Search index updated",
            "Push payload processed"
        ]

        return (messages.randomElement()!, categories.randomElement()!)
    }

    // MARK: - Privacy Issue Logs (For AI Analysis Demo)

    private static func generatePrivacyIssueLogs(logger: LogRService, count: Int) async {
        for i in 0..<count {
            let (message, category) = generatePrivacyIssueContent(index: i)
            let level: LogLevel = [.debug, .info, .warning].randomElement()!
            logMessage(logger: logger, level: level, message: message, category: category)
        }
    }

    private static func generatePrivacyIssueContent(index: Int) -> (String, LogCategory) {
        switch index % 8 {
        case 0: // Email exposure
            let email = mockEmails.randomElement()!
            return ("User login attempt for: \(email)", .authentication)
        case 1: // Phone number
            let phone = mockPhoneNumbers.randomElement()!
            return ("SMS verification sent to \(phone)", .authentication)
        case 2: // API token
            let token = mockTokens.randomElement()!
            return ("API request with token: \(token)", .api)
        case 3: // IP address
            let ip = mockIPs.randomElement()!
            return ("Request from IP: \(ip)", .network)
        case 4: // Location data
            let lat = Double.random(in: 30...50)
            let lon = Double.random(in: -120 ... -70)
            return ("User location: \(lat.formatted(.number.precision(.fractionLength(4)))), \(lon.formatted(.number.precision(.fractionLength(4))))",
                    .location)
        case 5: // Credit card (last 4 only is ok, but full number is PII)
            let card = mockCreditCards.randomElement()!
            return ("Payment processed for card: \(card)", .payment)
        case 6: // SSN
            let ssn = mockSSNs.randomElement()!
            return ("Identity verification SSN: \(ssn)", .security)
        default: // Personal name with identifier
            return ("Processing order for user_id=12345 (John Doe)", .user)
        }
    }

    // MARK: - Error Pattern Logs (For Issue Summary Demo)

    private static func generateErrorPatternLogs(logger: LogRService, count: Int) async {
        for i in 0..<count {
            if i % 3 == 0 {
                let (message, category) = recurringErrors.randomElement()!
                let level: LogLevel = i % 6 == 0 ? .fault : .error
                logMessage(logger: logger, level: level, message: message, category: category)
            } else {
                generateRandomError(logger: logger, index: i)
            }
        }
    }

    private static func generateRandomError(logger: LogRService, index: Int) {
        let errorMsg = errorMessages.randomElement()!
        let endpoint = networkEndpoints.randomElement()!

        let scenarios: [(String, LogCategory, LogLevel)] = [
            ("\(errorMsg) for \(endpoint)", .network, .error),
            ("Database query failed: \(errorMsg)", .database, .error),
            ("Cache invalidation error: \(errorMsg)", .cache, .warning),
            ("Background task failed: \(errorMsg)", .system, .error),
            ("Sync conflict detected: \(errorMsg)", .sync, .warning),
            ("Critical: Service unavailable - \(errorMsg)", .api, .fault)
        ]

        let (msg, cat, level) = scenarios.randomElement()!
        logMessage(logger: logger, level: level, message: msg, category: cat)
    }

    // MARK: - App Lifecycle Logs

    private static func generateAppLifecycleLogs(logger: LogRService) async {
        let lifecycleEvents = [
            ("Application launched", LogLevel.info, LogCategory.lifecycle),
            ("Scene entered foreground", LogLevel.debug, LogCategory.lifecycle),
            ("User session initialized", LogLevel.info, LogCategory.authentication),
            ("Core services started", LogLevel.notice, LogCategory.initialization),
            ("Database migrated to version 3", LogLevel.notice, LogCategory.database),
            ("Remote config loaded", LogLevel.info, LogCategory.configuration),
            ("Push notification permission granted", LogLevel.info, LogCategory.push),
            ("Analytics session started", LogLevel.debug, LogCategory.analytics)
        ]

        for (message, level, category) in lifecycleEvents {
            logMessage(logger: logger, level: level, message: message, category: category)
        }
    }

    // MARK: - Helpers

    private static func weightedRandomLevel(_ weights: [(LogLevel, Int)]) -> LogLevel {
        let total = weights.reduce(0) { $0 + $1.1 }
        var random = Int.random(in: 0..<total)

        for (level, weight) in weights {
            random -= weight
            if random < 0 {
                return level
            }
        }

        return .info
    }

    // MARK: - Quick Generation Methods

    static func generateSmallDataset(logger: LogRService) async {
        await generateComprehensiveLogs(logger: logger,
                                        count: 500,
                                        privacyIssues: 10,
                                        errorPatterns: 20)
    }

    static func generateMediumDataset(logger: LogRService) async {
        await generateComprehensiveLogs(logger: logger,
                                        count: 2_000,
                                        privacyIssues: 25,
                                        errorPatterns: 50)
    }

    static func generateLargeDataset(logger: LogRService) async {
        await generateComprehensiveLogs(logger: logger,
                                        count: 5_000,
                                        privacyIssues: 50,
                                        errorPatterns: 100)
    }
}
