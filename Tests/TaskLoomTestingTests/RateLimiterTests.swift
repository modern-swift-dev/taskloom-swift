import TaskLoom
import TaskLoomTesting
import Testing

@Suite(.timeLimit(.minutes(1))) struct RateLimiterTests {
    @Test func burstTokensAreAvailableImmediately() async throws {
        let clock = ManualClock()
        let limiter = RateLimiter(rate: 1, per: .seconds(1), burst: 3, clock: clock)
        for _ in 0 ..< 3 {
            try await limiter.acquire()
        }
        #expect(clock.sleepingCount == 0)
        #expect(await limiter.waitingCount == 0)
    }

    @Test func acquireAfterBurstWaitsForOneRefillInterval() async throws {
        let clock = ManualClock()
        let limiter = RateLimiter(rate: 3, per: .seconds(1), burst: 1, clock: clock)
        try await limiter.acquire()
        let task = Task {
            try await limiter.acquire()
            return clock.now.offset
        }
        try await clock.waitUntilSleeping()
        #expect(await limiter.waitingCount == 1)
        clock.advance(by: .milliseconds(333))
        try await clock.waitUntilSleeping()
        #expect(await limiter.waitingCount == 1)
        clock.advance(by: .milliseconds(1))
        #expect(try await task.value == .milliseconds(334))
        #expect(await limiter.waitingCount == 0)
    }

    @Test func refillIsCappedAtBurstAfterLongIdle() async throws {
        let clock = ManualClock()
        let limiter = RateLimiter(rate: 1, per: .seconds(1), burst: 2, clock: clock)
        try await limiter.acquire()
        try await limiter.acquire()
        clock.advance(by: .seconds(60))
        try await limiter.acquire()
        try await limiter.acquire()
        #expect(clock.sleepingCount == 0)
        let task = Task {
            try await limiter.acquire()
            return clock.now.offset
        }
        try await clock.waitUntilSleeping()
        #expect(await limiter.waitingCount == 1)
        clock.advance(by: .seconds(1))
        #expect(try await task.value == .seconds(61))
    }

    @Test func fractionalRefillsAddUpWithoutDrift() async throws {
        let clock = ManualClock()
        let limiter = RateLimiter(rate: 3, per: .seconds(1), burst: 1, clock: clock)
        try await limiter.acquire()
        var tasks: [Task<Void, any Error>] = []
        for index in 1 ... 3 {
            tasks.append(Task { try await limiter.acquire() })
            try await waitForWaitingCount(index, on: limiter)
        }
        // Tokens are due at 1/3 s, 2/3 s and exactly 1 s; each wake-up is rounded up to the next millisecond.
        for (waiting, step) in [(2, Duration.milliseconds(333)), (1, .milliseconds(332)), (0, .milliseconds(332))] {
            try await clock.waitUntilSleeping()
            clock.advance(by: step)
            #expect(clock.sleepingCount == 1)
            #expect(await limiter.waitingCount == waiting + 1)
            clock.advance(by: .milliseconds(1))
            try await waitForWaitingCount(waiting, on: limiter)
        }
        #expect(clock.now.offset == .seconds(1))
        for task in tasks {
            try await task.value
        }
    }

    @Test func waitersAreServedInArrivalOrder() async throws {
        let clock = ManualClock()
        let limiter = RateLimiter(rate: 1, per: .seconds(1), burst: 1, clock: clock)
        try await limiter.acquire()
        var waiters: [Task<Void, any Error>] = []
        for index in 1 ... 3 {
            waiters.append(Task { try await limiter.acquire() })
            try await waitForWaitingCount(index, on: limiter)
        }
        for (index, waiter) in waiters.enumerated() {
            try await clock.waitUntilSleeping()
            clock.advance(by: .seconds(1))
            try await waiter.value
            #expect(await limiter.waitingCount == waiters.count - index - 1)
        }
    }

    @Test func laterCallerDoesNotOvertakeQueuedWaiter() async throws {
        let manual = ManualClock()
        let limiter = RateLimiter(rate: 1, per: .seconds(1), burst: 1, clock: LateWakingClock(base: manual))
        try await limiter.acquire()
        let first = Task { try await limiter.acquire() }
        try await waitForWaitingCount(1, on: limiter)
        try await manual.waitUntilSleeping()
        // The token is now due, but the limiter has not woken up to hand it to `first`.
        manual.advance(by: .seconds(1))
        let later = Task { try await limiter.acquire() }
        try await waitForWaitingCount(2, on: limiter)
        manual.advance(by: LateWakingClock.lag)
        try await first.value
        try await later.value
    }

    @Test func cancelledHeadWaiterThrowsAndNextWaiterIsServedOnTime() async throws {
        let clock = ManualClock()
        let limiter = RateLimiter(rate: 1, per: .seconds(1), burst: 1, clock: clock)
        try await limiter.acquire()
        let head = Task { try await limiter.acquire() }
        try await waitForWaitingCount(1, on: limiter)
        let next = Task {
            try await limiter.acquire()
            return clock.now.offset
        }
        try await waitForWaitingCount(2, on: limiter)
        head.cancel()
        await #expect(throws: CancellationError.self) { try await head.value }
        #expect(await limiter.waitingCount == 1)
        try await clock.waitUntilSleeping()
        clock.advance(by: .seconds(1))
        #expect(try await next.value == .seconds(1))
    }

    @Test func cancellingTheOnlyWaiterKeepsItsToken() async throws {
        let clock = ManualClock()
        let limiter = RateLimiter(rate: 1, per: .seconds(1), burst: 1, clock: clock)
        try await limiter.acquire()
        let waiter = Task { try await limiter.acquire() }
        try await clock.waitUntilSleeping()
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        #expect(await limiter.waitingCount == 0)
        clock.advance(by: .seconds(1))
        try await limiter.acquire()
        let afterRefill = Task { try await limiter.acquire() }
        try await waitForWaitingCount(1, on: limiter)
        try await clock.waitUntilSleeping()
        clock.advance(by: .seconds(1))
        try await afterRefill.value
    }

    @Test func alreadyCancelledCallerThrowsWithoutTakingToken() async throws {
        let clock = ManualClock()
        let limiter = RateLimiter(rate: 1, per: .seconds(1), burst: 1, clock: clock)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await limiter.acquire()
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        try await limiter.acquire()
        #expect(clock.sleepingCount == 0)
        #expect(await limiter.waitingCount == 0)
    }

    @Test func limitedOperationStartsWhenTokenIsAvailable() async throws {
        let clock = ManualClock()
        let limiter = RateLimiter(rate: 1, per: .seconds(1), burst: 1, clock: clock)
        let operation = AsyncOperation { clock.now.offset }.limited(by: limiter)
        #expect(try await operation.execute() == .zero)
        let second = Task { try await operation.execute() }
        try await clock.waitUntilSleeping()
        clock.advance(by: .seconds(1))
        #expect(try await second.value == .seconds(1))
    }

    @Test func limitedTaskStartsWhenTokenIsAvailable() async throws {
        let clock = ManualClock()
        let limiter = RateLimiter(rate: 1, per: .seconds(1), burst: 1, clock: clock)
        let operation = AsyncTask { clock.now.offset }.limited(by: limiter)
        #expect(try await operation.execute() == .zero)
        let second = Task { try await operation.execute() }
        try await clock.waitUntilSleeping()
        clock.advance(by: .seconds(1))
        #expect(try await second.value == .seconds(1))
    }

    @Test func traceShowsWaitingForPermitWhileWaitingForToken() async throws {
        let clock = ManualClock()
        let recorder = OperationTraceRecorder(recordsEvents: true)
        let limiter = RateLimiter(rate: 1, per: .seconds(1), burst: 1, clock: clock)
        try await limiter.acquire()
        let task = Task {
            try await AsyncOperation { 1 }.limited(by: limiter).traced("limited", recorder: recorder).execute()
        }
        try await waitForWaitingCount(1, on: limiter)
        #expect(await recorder.activeOperations().first?.waitingForPermit == true)
        try await clock.waitUntilSleeping()
        clock.advance(by: .seconds(1))
        #expect(try await task.value == 1)
        #expect(await recorder.events().map(\.kind) == [.started, .waitingForPermit, .acquiredPermit, .succeeded])
    }

    @Test func traceReportsCancelledTokenWait() async throws {
        let recorder = OperationTraceRecorder(recordsEvents: true)
        let limiter = RateLimiter(rate: 1, per: .seconds(1), burst: 1, clock: ManualClock())
        try await limiter.acquire()
        let task = Task {
            try await AsyncOperation { 1 }.limited(by: limiter).traced("limited", recorder: recorder).execute()
        }
        try await waitForWaitingCount(1, on: limiter)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        let kinds = await recorder.events().map(\.kind)
        #expect(kinds.filter { $0 != .cancellationRequested } == [.started, .waitingForPermit, .permitWaitCancelled, .failed])
    }

    private func waitForWaitingCount(_ count: Int, on limiter: RateLimiter) async throws {
        while await limiter.waitingCount != count {
            try Task.checkCancellation()
            await Task.yield()
        }
    }
}

/// Reads time from a `ManualClock` but wakes sleepers late, so a token can fall due while its waiter is still queued.
private struct LateWakingClock: Clock {
    static let lag = Duration.seconds(3600)
    let base: ManualClock

    var now: ManualClock.Instant {
        base.now
    }

    var minimumResolution: Duration {
        base.minimumResolution
    }

    func sleep(until deadline: ManualClock.Instant, tolerance: Duration? = nil) async throws {
        try await base.sleep(until: deadline.advanced(by: Self.lag))
    }
}
