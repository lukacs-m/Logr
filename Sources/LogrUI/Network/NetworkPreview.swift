//
//  NetworkPreview.swift
//  LogrUI
//

import Logr
import LogrNetwork

/// A few recorded requests for the network previews.
enum NetworkPreview {
    static func service() -> LogR {
        let logger = LogR(configuration: LogrConfiguration(mirrorToOSLog: false))
        let requests: [(String, String, Int?, Double, LogLevel)] = [
            ("GET", "/v1/users/42", 200, 84.2, .info),
            ("POST", "/v1/login", 401, 132.5, .warning),
            ("GET", "/v1/feed?page=2&token=<private>", 503, 1_204, .error),
            ("PUT", "/v1/settings", nil, 30_000, .error)
        ]
        for (method, path, status, duration, level) in requests {
            var metadata: [String: LogMetadataValue] = [
                HTTPLogFields.method: .string(method),
                HTTPLogFields.url: .string("https://api.example.com" + path),
                HTTPLogFields.durationMilliseconds: .double(duration),
                HTTPLogFields.requestHeaders: ["Accept": "application/json", "Authorization": "<private>"],
                HTTPLogFields.requestBytes: 0
            ]
            if let status {
                metadata[HTTPLogFields.status] = .int(status)
                metadata[HTTPLogFields.responseBytes] = 4_312
                metadata[HTTPLogFields.responseHeaders] = ["Content-Type": "application/json"]
                metadata[HTTPLogFields.networkProtocol] = "h2"
                metadata[HTTPLogFields.reusedConnection] = false
                metadata[HTTPLogFields.domainLookupMilliseconds] = 4.1
                metadata[HTTPLogFields.connectMilliseconds] = 18.3
                metadata[HTTPLogFields.secureConnectionMilliseconds] = 22.7
                metadata[HTTPLogFields.requestMilliseconds] = 0.4
                metadata[HTTPLogFields.waitMilliseconds] = .double(duration - 52)
                metadata[HTTPLogFields.responseMilliseconds] = 6.2
            } else {
                metadata[HTTPLogFields.error] = "NSURLErrorDomain -1001"
            }
            let outcome = status.map(String.init) ?? "failed"
            let shownPath = String(path.prefix { $0 != "?" })
            logger.log(level: level, message: LogMessage("\(method) \(shownPath) → \(outcome)", privacy: .public),
                       category: .http, metadata: metadata)
        }
        return logger
    }
}
