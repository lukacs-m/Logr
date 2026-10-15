/// Metadata that every entry logged inside a scope carries, without passing it to each call.
///
/// ```swift
/// await LogContext.with(["requestID": .string(id)]) {
///     await sync()   // every entry logged inside carries requestID
/// }
/// ```
///
/// The metadata is task-local: it applies on the current task, to its child tasks (task groups, `async let`)
/// and to tasks it starts with `Task { }`, and not to `Task.detached`. Nested scopes merge key by key (a value is
/// replaced, never merged into), the inner value winning on a clash. Whatever the ``LogRService``,
/// ``LogRService/log(level:message:category:file:function:line:metadata:)`` and the level helpers merge it
/// under the metadata passed to the call, so the call site wins on a clash. Like all metadata, it is stored as
/// given, never redacted.
public enum LogContext {
    @TaskLocal private static var current: [String: LogMetadataValue] = [:]

    /// The metadata of the innermost enclosing scope, merged with every outer one. Empty outside any scope.
    public static var metadata: [String: LogMetadataValue] {
        current
    }

    /// Runs `operation` with `metadata` merged over the current context.
    ///
    /// - Parameters:
    ///   - metadata: The values to add; they replace values of the enclosing scopes with the same key.
    ///   - operation: The work that logs with the context. Runs on the caller's thread.
    /// - Returns: The value `operation` returns.
    public static func with<R>(_ metadata: [String: LogMetadataValue], operation: () throws -> R) rethrows -> R {
        try $current.withValue(merged(metadata), operation: operation)
    }

    /// Runs `operation` with `metadata` merged over the current context.
    ///
    /// - Parameters:
    ///   - metadata: The values to add; they replace values of the enclosing scopes with the same key.
    ///   - isolation: The actor `operation` runs on. Defaults to the caller's.
    ///   - operation: The work that logs with the context. Runs on the caller's actor, so it may touch the
    ///     caller's state and need not be `Sendable`.
    /// - Returns: The value `operation` returns.
    public static func with<R>(_ metadata: [String: LogMetadataValue],
                               isolation: isolated (any Actor)? = #isolation,
                               operation: () async throws -> R) async rethrows -> R {
        // Swift 6.4 deprecates the `isolation:` overload, the only one in Swift 6.3. There, `operation` passed
        // as is runs off the actor when it is `nonisolated(nonsending)`; a closure capturing `isolation` does not.
        #if compiler(>=6.4)
        try await $current.withValue(merged(metadata), operation: operation)
        #else
        try await $current.withValue(merged(metadata), operation: {
            _ = isolation
            return try await operation()
        }, isolation: isolation)
        #endif
    }

    /// `callSite` merged over the current context, the call site winning on a key clash.
    static func metadata(mergedWith callSite: [String: LogMetadataValue]?) -> [String: LogMetadataValue]? {
        let context = current
        guard !context.isEmpty else { return callSite }
        return callSite.map { context.merging($0) { _, callSite in callSite } } ?? context
    }

    private static func merged(_ inner: [String: LogMetadataValue]) -> [String: LogMetadataValue] {
        current.merging(inner) { _, inner in inner }
    }
}
