import TaskLoom
import TaskLoomTesting
import Testing

struct OperationClockTests {
    private enum Failure: Error { case transient }
    private actor Attempts {
        var count = 0
        func next() -> Int {
            count += 1; return count
        }
    }

    @Test func retryAdvancesUsingInjectedClockAndRecordsAttempt() async throws {
        let clock = ManualClock()
        let attempts = Attempts()
        let recorder = OperationTraceRecorder(recordsEvents: true)
        let task = Task {
            try await AsyncOperation {
                let attempt = await attempts.next()
                if attempt == 1 {
                    throw Failure.transient
                }
                return attempt
            }.retry(3, backoff: .constant(.seconds(5)), clock: clock)
                .traced("retry", recorder: recorder).execute()
        }
        try await clock.waitUntilSleeping()
        #expect(await attempts.count == 1)
        clock.advance(by: .seconds(5))
        #expect(try await task.value == 2)
        let events = await recorder.events()
        #expect(events.map(\.kind) == [.started, .retrying(attempt: 2, delay: .seconds(5)), .succeeded])
    }

    @Test func timeoutCancelsWorkUsingInjectedClock() async throws {
        let clock = ManualClock()
        let task = Task {
            try await AsyncOperation {
                try await clock.sleep(for: .seconds(100))
                return 1
            }.timeout(.seconds(5), clock: clock).execute()
        }
        try await clock.waitUntilSleeping(count: 2)
        clock.advance(by: .seconds(5))
        do { _ = try await task.value; Issue.record("Expected timeout") } catch { #expect((error as? AsyncOperationError) == .timeout(.seconds(5))) }
        #expect(clock.sleepingCount == 0)
    }

    @Test func cancellationDuringBackoffStopsRetries() async throws {
        let clock = ManualClock()
        let attempts = Attempts()
        let task = Task {
            try await AsyncOperation<Int> {
                _ = await attempts.next()
                throw Failure.transient
            }.retry(3, backoff: .constant(.seconds(5)), clock: clock).execute()
        }
        try await clock.waitUntilSleeping()
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") } catch { #expect(error is CancellationError) }
        #expect(await attempts.count == 1)
        #expect(clock.sleepingCount == 0)
    }

    @Test func throwingDelayedTaskPropagatesCancellation() async throws {
        let clock = ManualClock()
        let task: Task<Void, any Error> = DelayedTask(delay: .seconds(5), clock: clock) {
            Issue.record("Cancelled delay must not execute its handler")
        }
        try await clock.waitUntilSleeping()
        task.cancel()
        do { try await task.value; Issue.record("Expected cancellation") } catch { #expect(error is CancellationError) }
        #expect(clock.sleepingCount == 0)
    }
}
