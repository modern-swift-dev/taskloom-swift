import TaskLoom
import TaskLoomTesting
import Testing

struct ManualClockTests {
    @Test func deadlinesAndCancellation() async throws {
        let clock = ManualClock()
        let first = Task { try await clock.sleep(for: .seconds(2)) }
        let second = Task { try await clock.sleep(for: .seconds(5)) }
        try await clock.waitUntilSleeping(count: 2)
        clock.advance(by: .seconds(2))
        try await first.value
        #expect(clock.sleepingCount == 1)
        #expect(clock.now.offset == .seconds(2))
        second.cancel()
        await #expect(throws: CancellationError.self) { try await second.value }
        #expect(clock.sleepingCount == 0)
    }

    @Test func cancelledBeforeRegistering() async {
        let clock = ManualClock()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await clock.sleep(for: .seconds(1))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(clock.sleepingCount == 0)
    }

    @Test func observerCancellation() async {
        let clock = ManualClock()
        let observer = Task { try await clock.waitUntilSleeping() }
        observer.cancel()
        await #expect(throws: CancellationError.self) { try await observer.value }
    }

    @Test @MainActor func delayedTaskUsesClock() async throws {
        let clock = ManualClock()
        var called = false
        let task = DelayedTask(delay: .seconds(3), clock: clock) { called = true }
        try await clock.waitUntilSleeping()
        #expect(!called)
        clock.advance(by: .seconds(3))
        await task.value
        #expect(called)
    }

    @Test @MainActor func cancelledDelayDoesNotInvokeHandler() async throws {
        let clock = ManualClock()
        var called = false
        let task = DelayedTask(delay: .seconds(3), clock: clock) { called = true }
        try await clock.waitUntilSleeping()
        task.cancel()
        await task.value
        #expect(!called)
        #expect(clock.sleepingCount == 0)
    }

    @Test @MainActor func repeatingTaskUsesClockForEveryIteration() async throws {
        let clock = ManualClock()
        var iterations = 0
        let task = RepeatingTask(interval: .seconds(1), clock: clock) {
            iterations += 1
            return iterations < 2
        }
        try await clock.waitUntilSleeping()
        clock.advance(by: .seconds(1))
        try await clock.waitUntilSleeping()
        #expect(iterations == 1)
        clock.advance(by: .seconds(1))
        await task.value
        #expect(iterations == 2)
    }

    @Test func timeoutUsesClock() async throws {
        let clock = ManualClock()
        let task = Task {
            await AsyncTask {
                try? await clock.sleep(for: .seconds(100))
                return 42
            }.timeout(.seconds(5), clock: clock, default: 0).execute()
        }
        try await clock.waitUntilSleeping(count: 2)
        clock.advance(by: .seconds(5))
        #expect(await task.value == 0)
        #expect(clock.sleepingCount == 0)
    }
}
