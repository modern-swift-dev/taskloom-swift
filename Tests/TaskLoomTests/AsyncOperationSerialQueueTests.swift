@testable import TaskLoom
import Testing

@Suite(.timeLimit(.minutes(1))) struct AsyncOperationSerialQueueTests {
    @Test func returnsTheValueAndRethrowsTheError() async throws {
        let queue = AsyncOperationSerialQueue(name: "Results")
        #expect(try await queue.enqueue { 42 } == 42)
        await #expect(throws: Failure(id: 1)) {
            try await queue.enqueue { throw Failure(id: 1) }
        }
    }

    @Test func runsOneOperationAtATime() async throws {
        let queue = AsyncOperationSerialQueue(name: "Serial")
        let events = EventLog()
        let firstStarted = TestSignal()
        let releaseFirst = TestSignal()
        let first = Task {
            try await queue.enqueue {
                await events.append("first started")
                await firstStarted.signal()
                await releaseFirst.wait()
                await events.append("first finished")
            }
        }
        await firstStarted.wait()
        let second = Task {
            try await queue.enqueue { await events.append("second started") }
        }
        try await waitUntil { await queue.waitingCount == 1 }
        #expect(await events.entries == ["first started"])

        await releaseFirst.signal()
        try await first.value
        try await second.value
        #expect(await events.entries == ["first started", "first finished", "second started"])
    }

    @Test func runsSequentialEnqueuesFromOneTaskInOrder() async throws {
        let queue = AsyncOperationSerialQueue(name: "Sequential FIFO")
        let events = EventLog()
        for index in 0 ..< 5 {
            try await queue.enqueue { await events.append("\(index)") }
        }
        #expect(await events.entries == ["0", "1", "2", "3", "4"])
    }

    @Test @MainActor func runsCallsFromOneIsolationContextInCallOrder() async throws {
        let queue = AsyncOperationSerialQueue(name: "MainActor FIFO")
        let events = EventLog()
        let releaseBlocker = TestSignal()
        let blocker = Task { try await queue.enqueue { await releaseBlocker.wait() } }
        try await waitUntil { await queue.isBusy }
        // Each task starts on the main actor in creation order and reaches the queue in that order.
        let callers = (0 ..< 10).map { index in
            Task { try await queue.enqueue { await events.append("\(index)") } }
        }
        try await waitUntil { await queue.waitingCount == 10 }

        await releaseBlocker.signal()
        try await blocker.value
        for caller in callers {
            try await caller.value
        }
        #expect(await events.entries == (0 ..< 10).map { "\($0)" })
    }

    @Test func cancelledQueuedCallerIsSkippedAndLeavesPromptly() async throws {
        let queue = AsyncOperationSerialQueue(name: "Skip on cancel")
        let events = EventLog()
        let releaseFirst = TestSignal()
        let first = Task { try await queue.enqueue { await releaseFirst.wait() } }
        try await waitUntil { await queue.isBusy }
        let second = Task {
            try await queue.enqueue { await events.append("second ran") }
        }
        try await waitUntil { await queue.waitingCount == 1 }

        second.cancel()
        // The first operation is still suspended, so this returning proves the caller left promptly.
        await #expect(throws: CancellationError.self) { try await second.value }
        #expect(await queue.waitingCount == 0)

        await releaseFirst.signal()
        try await first.value
        try await queue.enqueue { await events.append("third ran") }
        #expect(await events.entries == ["third ran"])
    }

    @Test func alreadyCancelledCallerDoesNotRunItsOperation() async {
        let queue = AsyncOperationSerialQueue(name: "Already cancelled")
        let events = EventLog()
        let caller = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await queue.enqueue { await events.append("ran") }
        }
        await #expect(throws: CancellationError.self) { try await caller.value }
        #expect(await events.entries.isEmpty)
        #expect(await queue.isBusy == false)
    }

    @Test func cancellingTheCallerCancelsItsRunningOperation() async throws {
        let queue = AsyncOperationSerialQueue(name: "Cancel running")
        let events = EventLog()
        let started = TestSignal()
        let caller = Task {
            try await queue.enqueue {
                await started.signal()
                await suspendUntilCancelled()
                await events.append("cancelled: \(Task.isCancelled)")
                try Task.checkCancellation()
            }
        }
        await started.wait()

        caller.cancel()
        await #expect(throws: CancellationError.self) { try await caller.value }
        #expect(await events.entries == ["cancelled: true"])
        #expect(try await queue.enqueue { 1 } == 1)
    }

    @Test func failingOperationDoesNotStopTheNextOne() async throws {
        let queue = AsyncOperationSerialQueue(name: "Failure")
        let releaseFirst = TestSignal()
        let first = Task {
            try await queue.enqueue {
                await releaseFirst.wait()
                throw Failure(id: 1)
            }
        }
        try await waitUntil { await queue.isBusy }
        let second = Task { try await queue.enqueue { 2 } }
        try await waitUntil { await queue.waitingCount == 1 }

        await releaseFirst.signal()
        await #expect(throws: Failure(id: 1)) { try await first.value }
        #expect(try await second.value == 2)
    }

    @Test func cancelAllFailsWaitersCancelsTheRunningOperationAndKeepsTheQueueUsable() async throws {
        let queue = AsyncOperationSerialQueue(name: "Cancel all")
        let events = EventLog()
        let started = TestSignal()
        let running = Task {
            try await queue.enqueue {
                await started.signal()
                await suspendUntilCancelled()
                await events.append("running cancelled: \(Task.isCancelled)")
                try Task.checkCancellation()
            }
        }
        await started.wait()
        let waiting = (0 ..< 2).map { index in
            Task { try await queue.enqueue { await events.append("waiter \(index) ran") } }
        }
        try await waitUntil { await queue.waitingCount == 2 }

        await queue.cancelAll()
        for waiter in waiting {
            await #expect(throws: CancellationError.self) { try await waiter.value }
        }
        await #expect(throws: CancellationError.self) { try await running.value }
        #expect(await events.entries == ["running cancelled: true"])

        #expect(try await queue.enqueue { 3 } == 3)
    }

    @Test func cancelAllOnAnIdleQueueIsHarmless() async throws {
        let queue = AsyncOperationSerialQueue(name: "Idle cancel all")
        await queue.cancelAll()
        #expect(try await queue.enqueue { 1 } == 1)
    }

    @Test func operationThatIgnoresCancelAllKeepsItsResultAndHoldsTheQueue() async throws {
        let queue = AsyncOperationSerialQueue(name: "Uncooperative")
        let events = EventLog()
        let started = TestSignal()
        let releaseRunning = TestSignal()
        let running = Task {
            try await queue.enqueue {
                await started.signal()
                await releaseRunning.wait()
                await events.append("running finished")
                return 1
            }
        }
        await started.wait()

        await queue.cancelAll()
        let later = Task {
            try await queue.enqueue {
                await events.append("later ran")
                return 2
            }
        }
        try await waitUntil { await queue.waitingCount == 1 }
        #expect(await events.entries.isEmpty)

        await releaseRunning.signal()
        #expect(try await running.value == 1)
        #expect(try await later.value == 2)
        #expect(await events.entries == ["running finished", "later ran"])
    }

    @Test func operationCanEnqueueOntoAnotherQueue() async throws {
        let outer = AsyncOperationSerialQueue(name: "Outer")
        let inner = AsyncOperationSerialQueue(name: "Inner")
        let value = try await outer.enqueue {
            try await inner.enqueue { 1 } + 1
        }
        #expect(value == 2)
    }

    #if os(macOS) || os(Linux)
        @Test func enqueuingOntoTheSameQueueFromItsOperationStopsTheProcess() async {
            await #expect(processExitsWith: .failure) {
                let queue = AsyncOperationSerialQueue(name: "Reentrant")
                _ = try? await queue.enqueue {
                    try await queue.enqueue { 1 }
                }
            }
        }
    #endif

    @Test func acceptsMainActorOperations() async throws {
        let queue = AsyncOperationSerialQueue(name: "MainActor operation")
        let value = try await queue.enqueue { @MainActor in
            MainActor.assertIsolated()
            return 1
        }
        #expect(value == 1)
    }
}

private struct Failure: Error, Equatable {
    let id: Int
}

private actor EventLog {
    private(set) var entries: [String] = []

    func append(_ entry: String) {
        entries.append(entry)
    }
}

/// Suspends until the current task is cancelled.
private func suspendUntilCancelled() async {
    let (stream, continuation) = AsyncStream<Never>.makeStream()
    await withTaskCancellationHandler {
        for await _ in stream {}
    } onCancel: {
        continuation.finish()
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
