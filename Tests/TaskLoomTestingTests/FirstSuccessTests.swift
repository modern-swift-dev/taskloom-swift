import TaskLoom
import TaskLoomTesting
import Testing

struct FirstSuccessTests {
    private enum Failure: Error, Equatable { case first, second, third }

    private actor Recorder {
        private(set) var events: [String] = []
        func record(_ event: String) {
            events.append(event)
        }
    }

    @Test func firstSuccessWinsOverEarlierFailure() async throws {
        let clock = ManualClock()
        let task = Task {
            try await AsyncOperation<Int>.firstSuccess([
                .fail(Failure.first),
                AsyncOperation {
                    try await clock.sleep(for: .seconds(5))
                    return 7
                }
            ]).execute()
        }
        try await clock.waitUntilSleeping()
        clock.advance(by: .seconds(5))
        #expect(try await task.value == 7)
    }

    @Test func allFailuresAreReportedInInputOrder() async throws {
        let clock = ManualClock()
        let completions = Recorder()
        let task = Task {
            try await AsyncOperation<Int>.firstSuccess([
                AsyncOperation {
                    try await clock.sleep(for: .seconds(3))
                    await completions.record("first")
                    throw Failure.first
                },
                AsyncOperation {
                    try await clock.sleep(for: .seconds(1))
                    await completions.record("second")
                    throw Failure.second
                },
                AsyncOperation {
                    await completions.record("third")
                    throw Failure.third
                }
            ]).execute()
        }
        try await clock.waitUntilSleeping(count: 2)
        clock.advance(by: .seconds(1))
        while await completions.events.count < 2 {
            await Task.yield()
        }
        clock.advance(by: .seconds(2))

        do {
            _ = try await task.value
            Issue.record("Expected allFailed")
        } catch let AsyncOperationError.allFailed(errors) {
            #expect(errors.compactMap { $0 as? Failure } == [.first, .second, .third])
        } catch {
            Issue.record("Expected allFailed, got \(error)")
        }
        #expect(await completions.events == ["third", "second", "first"])
    }

    @Test func losersAreCancelledOnFirstSuccess() async throws {
        let clock = ManualClock()
        let cancelled = Recorder()
        let task = Task {
            try await AsyncOperation<Int>.firstSuccess([
                AsyncOperation {
                    do {
                        try await clock.sleep(for: .seconds(100))
                    } catch {
                        await cancelled.record("loser")
                        throw error
                    }
                    return 1
                },
                AsyncOperation {
                    try await clock.sleep(for: .seconds(5))
                    return 2
                }
            ]).execute()
        }
        try await clock.waitUntilSleeping(count: 2)
        clock.advance(by: .seconds(5))
        #expect(try await task.value == 2)
        #expect(await cancelled.events == ["loser"])
        #expect(clock.sleepingCount == 0)
    }

    @Test func parentCancellationThrowsCancellationErrorNotAllFailed() async throws {
        let clock = ManualClock()
        let task = Task {
            try await AsyncOperation<Int>.firstSuccess([
                AsyncOperation {
                    try await clock.sleep(for: .seconds(100))
                    return 1
                },
                AsyncOperation {
                    try await clock.sleep(for: .seconds(100))
                    return 2
                }
            ]).execute()
        }
        try await clock.waitUntilSleeping(count: 2)
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(clock.sleepingCount == 0)
    }
}
