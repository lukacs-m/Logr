//
//  NetworkLoggerConfiguration.swift
//  LogrNetwork
//

/// What ``NetworkLogger`` redacts and whether it keeps bodies.
///
/// Names are matched ignoring case.
public struct NetworkLoggerConfiguration: Sendable, Hashable {
    /// Headers whose value is recorded as `<private>`, the session configuration's and cookies included.
    ///
    /// Defaults to `Authorization`, `Proxy-Authorization`, `Cookie`, `Set-Cookie`, `X-Api-Key`, `X-Auth-Token`,
    /// `X-Access-Token`, `X-CSRF-Token`, `X-XSRF-Token` and `X-Amz-Security-Token`.
    public var redactedHeaders: Set<String>

    /// Query items, and keys of JSON and form bodies at any depth (JSON carried in a string value included),
    /// whose value is recorded as `<private>`. A form or query name such as `user[password]` matches on any of
    /// its bracketed parts. The query of a `Location`, `Content-Location` or `Referer` header is redacted too.
    ///
    /// Defaults to `password`, `token`, `access_token`, `refresh_token`, `id_token`, `secret`, `client_secret`,
    /// `api_key`, and the presigned-URL items `X-Amz-Security-Token`, `X-Amz-Credential` and `X-Amz-Signature`.
    public var redactedKeys: Set<String>

    /// Whether to keep request and response bodies, encrypted, in a ring of the newest ``maxStoredBodies``.
    ///
    /// Off by default. Only textual bodies are kept (`text/*`, JSON, XML, form, JavaScript, GraphQL, as the
    /// `Content-Type` header says). JSON and form bodies are redacted with ``redactedKeys``; one that does not
    /// parse, nests deeper than 128 levels or exceeds 1 MiB (or ``maxBodyBytes`` if larger) cannot be redacted and
    /// is not kept. Other textual bodies, JSON sent as `text/plain` included, are kept as they are. A request
    /// whose entry the service filters out keeps no body, as long as the service, like `LogR`, evaluates
    /// `record`'s metadata only for entries it keeps.
    public var captureBodies: Bool

    /// The most bytes kept of each body, after redaction. Defaults to 64 KiB; ``NetworkLogger`` treats values
    /// below 1 as 1.
    public var maxBodyBytes: Int

    /// How many requests' bodies are kept, the newest. Defaults to 100; ``NetworkLogger`` treats values below 1
    /// as 1.
    public var maxStoredBodies: Int

    /// Creates a configuration.
    public init(redactedHeaders: Set<String> = [
        "Authorization",
        "Proxy-Authorization",
        "Cookie",
        "Set-Cookie",
        "X-Api-Key",
        "X-Auth-Token",
        "X-Access-Token",
        "X-CSRF-Token",
        "X-XSRF-Token",
        "X-Amz-Security-Token"
    ],
    redactedKeys: Set<String> = [
        "password",
        "token",
        "access_token",
        "refresh_token",
        "id_token",
        "secret",
        "client_secret",
        "api_key",
        "X-Amz-Security-Token",
        "X-Amz-Credential",
        "X-Amz-Signature"
    ],
    captureBodies: Bool = false,
    maxBodyBytes: Int = 64 * 1_024,
    maxStoredBodies: Int = 100) {
        self.redactedHeaders = redactedHeaders
        self.redactedKeys = redactedKeys
        self.captureBodies = captureBodies
        self.maxBodyBytes = maxBodyBytes
        self.maxStoredBodies = maxStoredBodies
    }
}
