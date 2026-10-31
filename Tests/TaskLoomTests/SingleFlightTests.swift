@testable import TaskLoom
import Testing

@Suite(.timeLimit(.minutes(1))) struct SingleFlightTests {
    @Test func concurrentCallersShareOneExecution() async throws {
        let flight = SingleFlight<String, Int>()
        let runs = Counter()
        let release = TestSignal()
        let callers = (0 ..< 5).map { _ in
            Task {
                try await flight.run(key: "a") {
                    await runs.increment()
                    await release.wait()
                    return 42
                }
            }
        }
        try await waitUntil { await flight.waiterCount(for: "a") == 5 }
        await release.signal()
        for caller in callers {
            #expect(try await caller.value == 42)
        }
        #expect(await runs.value == 1)
        #expect(await flight.waiterCount(for: "a") == nil)
    }

    @Test func allWaitersReceiveTheSameError() async throws {
        let flight = SingleFlight<String, Int>()
        let runs = Counter()
        let release = TestSignal()
        let callers = (0 ..< 3).map { _ in
            Task {
                try await flight.run(key: "a") {
                    let run = await runs.increment()
                    await release.wait()
                    throw Failure(run: run)
                }
            }
        }
        try await waitUntil { await flight.waiterCount(for: "a") == 3 }
        await release.signal()
        for caller in callers {
            await #expect(throws: Failure(run: 1)) { try await caller.value }
        }
        #expect(await flight.waiterCount(for: "a") == nil)
    }

    @Test func finishedSuccessIsNotCached() async throws {
        let flight = SingleFlight<String, Int>()
        let runs = Counter()
        let first = try await flight.run(key: "a") { await runs.increment() }
        let second = try await flight.run(key: "a") { await runs.increment() }
        #expect(first == 1)
        #expect(second == 2)
    }

    @Test func finishedFailureIsNotCached() async throws {
        let flight = SingleFlight<String, Int>()
        await #expect(throws: Failure(run: 1)) {
            try await flight.run(key: "a") { throw Failure(run: 1) }
        }
        #expect(try await flight.run(key: "a") { 2 } == 2)
    }

    @Test func differentKeysRunIndependently() async throws {
        let flight = SingleFlight<String, Int>()
        let releaseA = TestSignal()
        let callerA = Task {
            try await flight.run(key: "a") {
                await releaseA.wait()
                return 1
            }
        }
        try await waitUntil { await flight.waiterCount(for: "a") == 1 }
        #expect(try await flight.run(key: "b") { 2 } == 2)
        #expect(await flight.waiterCount(for: "a") == 1)
        await releaseA.signal()
        #expect(try await callerA.value == 1)
    }

    @Test func cancelledWaiterLeavesPromptlyWhileOthersGetTheValue() async throws {
        let flight = SingleFlight<String, Int>()
        let release = TestSignal()
        let operationCancelled = Recorder()
        let first = Task {
            try await flight.run(key: "a") {
                await release.wait()
                await operationCancelled.record(Task.isCancelled)
                return 42
            }
        }
        try await waitUntil { await flight.waiterCount(for: "a") == 1 }
        let second = Task { try await flight.run(key: "a") { 0 } }
        try await waitUntil { await flight.waiterCount(for: "a") == 2 }

        second.cancel()
        // The shared operation is still suspended, so this returning proves the waiter left promptly.
        await #expect(throws: CancellationError.self) { try await second.value }
        #expect(await flight.waiterCount(for: "a") == 1)

        await release.signal()
        #expect(try await first.value == 42)
        #expect(await operationCancelled.value == false)
    }

    @Test func cancellingEveryWaiterCancelsTheFlightAndClearsTheKey() async throws {
        let flight = SingleFlight<String, Int>()
        let release = TestSignal()
        let operationCancelled = Recorder()
        let callers = (0 ..< 2).map { _ in
            Task {
                try await flight.run(key: "a") {
                    await release.wait()
                    await operationCancelled.record(Task.isCancelled)
                    return 1
                }
            }
        }
        try await waitUntil { await flight.waiterCount(for: "a") == 2 }

        for caller in callers {
            caller.cancel()
            await #expect(throws: CancellationError.self) { try await caller.value }
        }
        #expect(await flight.waiterCount(for: "a") == nil)
        // The cancelled operation is still suspended, so this value comes from a new flight.
        #expect(try await flight.run(key: "a") { 2 } == 2)

        await release.signal()
        try await waitUntil { await operationCancelled.value != nil }
        #expect(await operationCancelled.value == true)
    }

    @Test func alreadyCancelledCallerDoesNotStartAFlight() async {
        let flight = SingleFlight<String, Int>()
        let runs = Counter()
        let caller = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await flight.run(key: "a") { await runs.increment() }
        }
        await #expect(throws: CancellationError.self) { try await caller.value }
        #expect(await runs.value == 0)
        #expect(await flight.waiterCount(for: "a") == nil)
    }

    @Test func staleCompletionDoesNotEvictANewerFlight() async throws {
        let flight = SingleFlight<String, Int>()
        let releaseOld = TestSignal()
        let oldReturned = TestSignal()
        let releaseNew = TestSignal()
        let old = Task {
            try await flight.run(key: "a") {
                await releaseOld.wait()
                await oldReturned.signal()
                return 1
            }
        }
        try await waitUntil { await flight.waiterCount(for: "a") == 1 }
        old.cancel()
        await #expect(throws: CancellationError.self) { try await old.value }

        let newer = Task {
            try await flight.run(key: "a") {
                await releaseNew.wait()
                return 2
            }
        }
        try await waitUntil { await flight.waiterCount(for: "a") == 1 }
        await releaseOld.signal()
        await oldReturned.wait()

        let joiner = Task { try await flight.run(key: "a") { 3 } }
        try await waitUntil { await flight.waiterCount(for: "a") == 2 }
        await releaseNew.signal()
        #expect(try await newer.value == 2)
        #expect(try await joiner.value == 2)
        #expect(await flight.waiterCount(for: "a") == nil)
    }
}

private struct Failure: Error, Equatable {
    let run: Int
}

private actor Counter {
    private(set) var value = 0

    @discardableResult
    func increment() -> Int {
        value += 1
        return value
    }
}

private actor Recorder {
    private(set) var value: Bool?

    func record(_ value: Bool) {
        self.value = value
    }
}

/// Yields until `condition` holds; ordering comes from actor state, not elapsed time.
/// Throws on cancellation so the suite's time limit can end a test that would never satisfy it.
private func waitUntil(_ condition: @Sendable () async -> Bool) async throws {
    while await !condition() {
        try Task.checkCancellation()
        await Task.yield()
    }
}
