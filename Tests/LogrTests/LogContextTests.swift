import Logr
import LogrTesting
import Testing

@Suite("LogContext scopes")
struct LogContextScopeTests {
    @Test func metadataIsEmptyOutsideAnyScope() {
        #expect(LogContext.metadata.isEmpty)
    }

    @Test func nestedScopesMergeAndTheInnerValueWins() async {
        await LogContext.with(["request": "1", "user": "a"]) {
            await LogContext.with(["request": "2", "screen": "home"]) {
                await Task.yield()
                #expect(LogContext.metadata == ["request": "2", "user": "a", "screen": "home"])
            }
            #expect(LogContext.metadata == ["request": "1", "user": "a"])
        }
        #expect(LogContext.metadata.isEmpty)
    }

    @Test func synchronousScopesMergeAndReturnTheResult() {
        let result = LogContext.with(["request": "1"]) {
            LogContext.with(["user": "a"]) { LogContext.metadata }
        }
        #expect(result == ["request": "1", "user": "a"])
        #expect(LogContext.metadata.isEmpty)
    }

    @Test func aThrowingOperationEndsTheScopeAndRethrows() async {
        struct Failure: Error {}
        #expect(throws: Failure.self) {
            try LogContext.with(["request": "1"]) { throw Failure() }
        }
        await #expect(throws: Failure.self) {
            try await LogContext.with(["request": "1"]) {
                await Task.yield()
                throw Failure()
            }
        }
        #expect(LogContext.metadata.isEmpty)
    }

    @Test func childTasksInheritTheContext() async {
        await LogContext.with(["request": "1"]) {
            let fromGroup = await withTaskGroup(of: [String: LogMetadataValue].self) { group in
                group.addTask { LogContext.metadata }
                return await group.next() ?? [:]
            }
            async let fromAsyncLet = LogContext.metadata
            let fromTask = await Task { LogContext.metadata }.value
            #expect(fromGroup == ["request": "1"])
            #expect(await fromAsyncLet == ["request": "1"])
            #expect(fromTask == ["request": "1"])
        }
    }

    @Test func detachedTasksDoNotInheritTheContext() async {
        await LogContext.with(["request": "1"]) {
            let fromDetached = await Task.detached { LogContext.metadata }.value
            #expect(fromDetached.isEmpty)
        }
    }

    @MainActor
    @Test func theOperationRunsOnTheCallersActor() async {
        let counter = Counter()
        await LogContext.with(["request": "1"]) {
            MainActor.assertIsolated()
            await Task.yield()
            MainActor.assertIsolated()
            counter.value += 1
        }
        #expect(counter.value == 1)
        #expect(await ContextActor().incrementInsideScope() == 1)
    }

    @MainActor
    @Test func theOperationRunsOnTheActorOfANonsendingCaller() async {
        let counter = Counter()
        await incrementInsideScope(counter)
        #expect(counter.value == 1)
    }

    @Test func theOperationRunsOnAnExplicitIsolation() async {
        let actor = ContextActor()
        await LogContext.with(["request": "1"], isolation: actor) { @Sendable in
            await Task.yield()
            actor.assertIsolated()
        }
    }
}

private final class Counter {
    var value = 0
}

/// Runs on its caller's actor; the closure it hands on must stay there too.
private nonisolated(nonsending) func incrementInsideScope(_ counter: Counter) async {
    await LogContext.with(["request": "1"]) {
        await Task.yield()
        MainActor.assertIsolated()
        counter.value += 1
    }
}

private actor ContextActor {
    var value = 0

    func incrementInsideScope() async -> Int {
        await LogContext.with(["request": "1"]) {
            await Task.yield()
            assertIsolated()
            value += 1
        }
        return value
    }
}

@Suite("LogR merges the LogContext")
struct LogContextLoggingTests {
    private let logger = LogR(cryptoService: LoggerCryptoService(store: InMemoryKeychainStore()))

    @Test func entriesCarryTheContext() async {
        await LogContext.with(["request": "1"]) {
            await Task.yield()
            logger.info("inside", category: .test)
        }
        logger.info("outside", category: .test)

        #expect(logger.recentLogs.map(\.message) == ["outside", "inside"])
        #expect(logger.recentLogs.map(\.metadata) == [nil, ["request": "1"]])
    }

    @Test func callSiteMetadataWinsOverTheContext() {
        LogContext.with(["request": "1", "user": "a"]) {
            logger.info("call", category: .test, metadata: ["request": "2", "screen": "home"])
        }
        #expect(logger.recentLogs.first?.metadata == ["request": "2", "user": "a", "screen": "home"])
    }

    @Test(arguments: [nil, [:]] as [[String: LogMetadataValue]?])
    func withoutContextMetadataIsKeptAsGiven(metadata: [String: LogMetadataValue]?) {
        logger.info("call", category: .test, metadata: metadata)
        #expect(logger.recentLogs.first?.metadata == metadata)
    }

    @Test func childTasksLogWithTheContext() async {
        let logger = logger
        await LogContext.with(["request": "1"]) {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { logger.info("child", category: .test) }
            }
        }
        #expect(logger.recentLogs.first?.metadata == ["request": "1"])
    }
}
