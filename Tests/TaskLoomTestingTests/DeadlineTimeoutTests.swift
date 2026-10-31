import TaskLoom
import TaskLoomTesting
import Testing

struct DeadlineTimeoutTests {
    private actor Counter {
        var value = 0
        func increment() {
            value += 1
        }
    }

    private func expectTimedOut(_ body: () async throws -> some Any) async {
        do {
            _ = try await body()
            Issue.record("Expected timedOut")
        } catch AsyncOperationError.timedOut {
            // Expected
        } catch {
            Issue.record("Expected timedOut, got \(error)")
        }
    }

    @Test func deadlineCancelsWorkWhenReached() async throws {
        let clock = ManualClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        let task = Task {
            try await AsyncOperation {
                try await clock.sleep(for: .seconds(100))
                return 1
            }.timeout(until: deadline, clock: clock).execute()
        }
        try await clock.waitUntilSleeping(count: 2)
        clock.advance(by: .seconds(4))
        await Task.yield()
        #expect(clock.sleepingCount == 2)
        clock.advance(by: .seconds(1))
        await expectTimedOut { try await task.value }
        #expect(clock.sleepingCount == 0)
    }

    @Test func deadlineDoesNotAffectWorkThatFinishesFirst() async throws {
        let clock = ManualClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        let task = Task {
            try await AsyncOperation {
                try await clock.sleep(for: .seconds(2))
                return 1
            }.timeout(until: deadline, clock: clock).execute()
        }
        try await clock.waitUntilSleeping(count: 2)
        clock.advance(by: .seconds(2))
        #expect(try await task.value == 1)
        #expect(clock.sleepingCount == 0)
    }

    @Test func stepsSharingOneDeadlineShareOneCutOff() async throws {
        let clock = ManualClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        let step = AsyncOperation {
            try await clock.sleep(for: .seconds(3))
            return 1
        }.timeout(until: deadline, clock: clock)
        let task = Task {
            try await step.flatMap { _ in step }.execute()
        }
        try await clock.waitUntilSleeping(count: 2)
        clock.advance(by: .seconds(3))
        try await clock.waitUntilSleeping(count: 2)
        clock.advance(by: .seconds(2))
        await expectTimedOut { try await task.value }
    }

    @Test func deadlineAlreadyPassedTimesOutWithoutRunningWork() async {
        let clock = ManualClock()
        clock.advance(by: .seconds(10))
        let started = Counter()
        let operation = AsyncOperation {
            await started.increment()
            return 1
        }.timeout(until: ManualClock.Instant(offset: .seconds(5)), clock: clock)
        await expectTimedOut { try await operation.execute() }
        #expect(await started.value == 0)
    }

    @Test func deadlineAlreadyPassedStillReportsParentCancellation() async throws {
        let clock = ManualClock()
        clock.advance(by: .seconds(10))
        let cancelled = Task {
            while !Task.isCancelled {
                await Task.yield()
            }
            return try await AsyncOperation { 1 }
                .timeout(until: ManualClock.Instant(offset: .seconds(5)), clock: clock).execute()
        }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
    }

    @Test func continuousClockConvenienceTimesOutPastDeadline() async {
        let operation = AsyncOperation {
            try await Task.sleep(for: .seconds(60))
            return 1
        }.timeout(until: ContinuousClock.now - .seconds(1))
        await expectTimedOut { try await operation.execute() }
    }

    @Test func durationFormThrowsTimedOut() async throws {
        let clock = ManualClock()
        let task = Task {
            try await AsyncOperation {
                try await clock.sleep(for: .seconds(100))
                return 1
            }.timeout(.seconds(5), clock: clock).execute()
        }
        try await clock.waitUntilSleeping(count: 2)
        clock.advance(by: .seconds(5))
        await expectTimedOut { try await task.value }
    }

    @Test func taskReturnsDefaultAtDeadline() async throws {
        let clock = ManualClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        let task = Task {
            await AsyncTask {
                try? await clock.sleep(for: .seconds(100))
                return 42
            }.timeout(until: deadline, clock: clock, default: 0).execute()
        }
        try await clock.waitUntilSleeping(count: 2)
        clock.advance(by: .seconds(5))
        #expect(await task.value == 0)
        #expect(clock.sleepingCount == 0)
    }

    @Test func taskReturnsDefaultWhenDeadlineAlreadyPassed() async {
        let clock = ManualClock()
        clock.advance(by: .seconds(10))
        let result = await AsyncTask { 42 }
            .timeout(until: ManualClock.Instant(offset: .seconds(5)), clock: clock, default: 0).execute()
        #expect(result == 0)
    }
}
