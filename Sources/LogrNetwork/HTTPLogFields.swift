//
//  HTTPLogFields.swift
//  LogrNetwork
//

/// The metadata keys of the entries ``NetworkLogger`` records, one entry per request, in category `.http`.
///
/// Every key is present on every entry except where noted. Durations are milliseconds as `.double`, sizes are
/// bytes as `.int`. Header and query values named in ``NetworkLoggerConfiguration`` read `<private>`.
///
/// ## Topics
///
/// ### Request and outcome
/// - ``method``
/// - ``url``
/// - ``status``
/// - ``error``
/// - ``durationMilliseconds``
///
/// ### Headers and sizes
/// - ``requestHeaders``
/// - ``responseHeaders``
/// - ``requestBytes``
/// - ``responseBytes``
/// - ``bodyID``
///
/// ### Connection and phase timings
/// - ``networkProtocol``
/// - ``reusedConnection``
/// - ``domainLookupMilliseconds``
/// - ``connectMilliseconds``
/// - ``secureConnectionMilliseconds``
/// - ``requestMilliseconds``
/// - ``waitMilliseconds``
/// - ``responseMilliseconds``
public enum HTTPLogFields {
    /// The request method, such as `GET`.
    public static let method = "http.method"
    /// The request URL without user, password or fragment, query values named in
    /// ``NetworkLoggerConfiguration/redactedKeys`` replaced by `<private>`.
    public static let url = "http.url"
    /// The response status code; absent when no response arrived.
    public static let status = "http.status"
    /// The failure, as `<domain> <code>` (`NSURLErrorDomain -1001`); present only when the request failed.
    public static let error = "http.error"
    /// From task creation to completion.
    public static let durationMilliseconds = "http.duration_ms"
    /// The request headers as sent to ``url`` (or looked up in the cache), those URLSession adds (configuration,
    /// cookies, `User-Agent`) included, as a dictionary of strings.
    public static let requestHeaders = "http.request_headers"
    /// The response headers, as a dictionary of strings; absent when no response arrived.
    public static let responseHeaders = "http.response_headers"
    /// The request body's size.
    public static let requestBytes = "http.request_bytes"
    /// The response body's size after decoding; absent when no response arrived.
    public static let responseBytes = "http.response_bytes"
    /// The protocol the last transaction used, such as `h2` or `http/1.1`; absent for cached or stubbed responses.
    public static let networkProtocol = "http.protocol"
    /// Whether the last transaction reused a connection; absent for cached or stubbed responses.
    public static let reusedConnection = "http.reused_connection"
    /// Where ``NetworkLogger/body(id:)`` finds the bodies; present only when a body was captured.
    public static let bodyID = "http.body_id"
    /// DNS lookup in the last transaction; absent when it did not happen (a reused connection, for instance).
    public static let domainLookupMilliseconds = "http.dns_ms"
    /// TCP connection setup in the last transaction, TLS excluded; absent when it did not happen.
    public static let connectMilliseconds = "http.connect_ms"
    /// TLS handshake in the last transaction; absent when it did not happen.
    public static let secureConnectionMilliseconds = "http.tls_ms"
    /// Sending the request in the last transaction; absent when not measured.
    public static let requestMilliseconds = "http.request_ms"
    /// From the request sent to the first response byte in the last transaction; absent when not measured.
    public static let waitMilliseconds = "http.wait_ms"
    /// Receiving the response in the last transaction; absent when not measured.
    public static let responseMilliseconds = "http.response_ms"
}
