import Synchronization
import TaskLoom
import TaskLoomTesting
import Testing

struct RetryDecisionTests {
    private enum Failure: Error { case transient, rateLimited }

    private actor Attempts {
        var count = 0
        func next() -> Int {
            count += 1; return count
        }
    }

    @Test func retryAfterSleepsExactDurationOnInjectedClock() async throws {
        let clock = ManualClock()
        let attempts = Attempts()
        let recorder = OperationTraceRecorder(recordsEvents: true)
        let task = Task {
            try await AsyncOperation {
                let attempt = await attempts.next()
                if attempt == 1 {
                    throw Failure.rateLimited
                }
                return attempt
            }.retry(3, backoff: .constant(.seconds(60)), clock: clock, decide: { _ in .retry(after: .seconds(2)) })
                .traced("retry-after", recorder: recorder).execute()
        }
        try await clock.waitUntilSleeping()
        #expect(await attempts.count == 1)
        clock.advance(by: .seconds(2))
        #expect(try await task.value == 2)
        let events = await recorder.events()
        #expect(events.map(\.kind) == [.started, .retrying(attempt: 2, delay: .seconds(2)), .succeeded])
    }

    @Test func retryUsesBackoffStrategyDelay() async throws {
        let clock = ManualClock()
        let attempts = Attempts()
        let task = Task {
            try await AsyncOperation {
                let attempt = await attempts.next()
                if attempt == 1 {
                    throw Failure.transient
                }
                return attempt
            }.retry(3, backoff: .constant(.seconds(5)), clock: clock, decide: { _ in .retry }).execute()
        }
        try await clock.waitUntilSleeping()
        clock.advance(by: .seconds(4))
        await Task.yield()
        #expect(await attempts.count == 1)
        clock.advance(by: .seconds(1))
        #expect(try await task.value == 2)
    }

    @Test func stopRethrowsErrorWithoutRetrying() async {
        let attempts = Attempts()
        let operation = AsyncOperation<Int> {
            _ = await attempts.next()
            throw Failure.rateLimited
        }.retry(4, decide: { _ in .stop })
        await #expect(throws: Failure.self) { try await operation.execute() }
        #expect(await attempts.count == 1)
    }

    @Test func decisionReceivesTheFailure() async throws {
        let attempts = Attempts()
        let operation = AsyncOperation<Int> {
            let attempt = await attempts.next()
            throw attempt == 1 ? Failure.transient : Failure.rateLimited
        }.retry(4, decide: { error in
            switch error as? Failure {
                case .transient: .retry
                default: .stop
            }
        })
        await #expect(throws: Failure.self) { try await operation.execute() }
        #expect(await attempts.count == 2)
    }

    @Test func cancellationIsNeverRetriedWhateverTheDecision() async {
        let attempts = Attempts()
        let decisions = Mutex(0)
        let operation = AsyncOperation<Int> {
            _ = await attempts.next()
            throw CancellationError()
        }.retry(4, decide: { _ in
            decisions.withLock { $0 += 1 }
            return .retry(after: .seconds(1))
        })
        await #expect(throws: CancellationError.self) { try await operation.execute() }
        #expect(await attempts.count == 1)
        #expect(decisions.withLock { $0 } == 0)
    }

    @Test func exhaustingAttemptsStillThrowsMaxRetriesExceeded() async {
        let clock = ManualClock()
        let attempts = Attempts()
        let task = Task {
            try await AsyncOperation<Int> {
                _ = await attempts.next()
                throw Failure.rateLimited
            }.retry(2, clock: clock, decide: { _ in .retry(after: .seconds(1)) }).execute()
        }
        do {
            try await clock.waitUntilSleeping()
            clock.advance(by: .seconds(1))
            _ = try await task.value
            Issue.record("Expected maxRetriesExceeded")
        } catch let AsyncOperationError.maxRetriesExceeded(attemptCount, lastError) {
            #expect(attemptCount == 2)
            #expect(lastError is Failure)
        } catch {
            Issue.record("Expected maxRetriesExceeded, got \(error)")
        }
        #expect(await attempts.count == 2)
    }

    @Test func cancellationDuringRetryAfterStopsRetries() async throws {
        let clock = ManualClock()
        let attempts = Attempts()
        let task = Task {
            try await AsyncOperation<Int> {
                _ = await attempts.next()
                throw Failure.rateLimited
            }.retry(3, clock: clock, decide: { _ in .retry(after: .seconds(30)) }).execute()
        }
        try await clock.waitUntilSleeping()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await attempts.count == 1)
        #expect(clock.sleepingCount == 0)
    }
}
