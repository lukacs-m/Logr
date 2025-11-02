import Foundation

//public actor ConfigurationManager {
//    private let configURL: URL
//    private let encoder = JSONEncoder()
//    private let decoder = JSONDecoder()
//    
//    public init(fileName: String = "logr_config.json") throws {
//        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
//        self.configURL = documentsPath.appendingPathComponent(fileName)
//        
//        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
//        encoder.dateEncodingStrategy = .iso8601
//        decoder.dateDecodingStrategy = .iso8601
//        
//        try createDefaultConfigIfNeededSync()
//    }
//    
//    nonisolated private func createDefaultConfigIfNeededSync() throws {
//        if !FileManager.default.fileExists(atPath: configURL.path) {
//            let data = try encoder.encode(LogrConfiguration.default)
//            try data.write(to: configURL, options: .atomic)
//        }
//    }
//    
//    public func loadConfiguration() throws -> LogrConfiguration {
//        let data = try Data(contentsOf: configURL)
//        return try decoder.decode(LogrConfiguration.self, from: data)
//    }
//    
//    public func saveConfiguration(_ configuration: LogrConfiguration) throws {
//        let data = try encoder.encode(configuration)
//        try data.write(to: configURL, options: .atomic)
//    }
//    
//    public func updateConfiguration<T>(_ keyPath: WritableKeyPath<LogrConfiguration, T>, value: T) throws {
//        var config = try loadConfiguration()
//        config[keyPath: keyPath] = value
//        try saveConfiguration(config)
//    }
//    
//    public func resetToDefault() throws {
//        try saveConfiguration(.default)
//    }
//    
//    public func getConfigurationURL() -> URL {
//        return configURL
//    }
//}
//
//extension LogrConfiguration {
//    public func toJSONString() throws -> String {
//        let encoder = JSONEncoder()
//        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
//        encoder.dateEncodingStrategy = .iso8601
//        
//        let data = try encoder.encode(self)
//        return String(data: data, encoding: .utf8) ?? ""
//    }
//    
//    public static func fromJSONString(_ json: String) throws -> LogrConfiguration {
//        guard let data = json.data(using: .utf8) else {
//            throw ConfigurationError.invalidJSON
//        }
//        
//        let decoder = JSONDecoder()
//        decoder.dateDecodingStrategy = .iso8601
//        
//        return try decoder.decode(LogrConfiguration.self, from: data)
//    }
//}
//
//public enum ConfigurationError: Error, LocalizedError {
//    case invalidJSON
//    case fileNotFound
//    case encodingFailed
//    case decodingFailed
//    
//    public var errorDescription: String? {
//        switch self {
//        case .invalidJSON:
//            return "Invalid JSON format in configuration"
//        case .fileNotFound:
//            return "Configuration file not found"
//        case .encodingFailed:
//            return "Failed to encode configuration"
//        case .decodingFailed:
//            return "Failed to decode configuration"
//        }
//    }
//}
