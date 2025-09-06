import Foundation
import OSLog

@frozen
public enum PrivacyLevel: Sendable {
    case `public`
    case `private`
    case sensitive
    
    public var osLogPrivacy: OSLogPrivacy {
        switch self {
        case .public: return .public
        case .private: return .private
        case .sensitive: return .sensitive
        }
    }
}

public struct PrivateString: Sendable {
    let value: String
    let privacy: PrivacyLevel
    
    public init(_ value: String, privacy: PrivacyLevel = .private) {
        self.value = value
        self.privacy = privacy
    }
    
    public var redacted: String {
        switch privacy {
        case .public:
            return value
        case .private:
            return "<private>"
        case .sensitive:
            return "<sensitive>"
        }
    }
}

extension PrivateString: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value, privacy: .private)
    }
}