import Foundation

/// An actor-based token bucket that limits how often work may start.
///
/// Use `RateLimiter` for "N per period" limits, such as an API quota of ten requests per second.
/// The bucket holds at most `burst` tokens and starts full. Tokens refill continuously at
/// `rate / period`, and each ``acquire()`` takes one, waiting when none is available.
/// Unlike an ``AsyncSemaphore`` permit, a token is consumed rather than released, so the limiter
/// bounds how often work starts, not how much runs at once.
///
/// ```swift
/// let limiter = RateLimiter(rate: 10, per: .seconds(1), burst: 10)
///
/// let user = try await AsyncOperation { try await api.fetchUser(id) }
///     .limited(by: limiter)
///     .execute()
/// ```
///
/// Waiters are served in arrival order: a later caller never takes a token ahead of an earlier
/// waiter, even when a token is available when it calls. A caller cancelled while waiting throws
/// `CancellationError` and consumes no token.
public actor RateLimiter {

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }

    /// Credit accrues `rate` units per attosecond, so one token costs the period in attoseconds.
    /// Integer arithmetic keeps fractional tokens exact, so refills never drift.
    private let tokenCost: Int128
    private let capacity: Int128
    private let rate: Int128
    /// The injected clock, erased to offsets from the instant the limiter was created.
    private let now: @Sendable () -> Duration
    private let sleep: @Sendable (_ until: Duration) async throws -> Void

    private var credit: Int128
    private var lastRefill: Duration = .zero
    private var waiters: [Waiter] = []
    /// The only task that serves waiters after they have queued.
    private var drainer: Task<Void, Never>?
    private var drainGeneration = 0

    /// Creates a full token bucket that refills on the given clock.
    /// - Parameters:
    ///   - rate: The number of tokens added per period. Must be greater than 0.
    ///   - period: The time over which `rate` tokens are added. Must be greater than zero.
    ///   - burst: The maximum number of tokens the bucket holds, and the number it starts with. Must be greater than 0.
    ///   - clock: The clock used to measure refills and to wait for tokens.
    public init<C: Clock>(rate: Int, per period: Duration, burst: Int, clock: C) where C.Duration == Duration {
        precondition(rate > 0, "Rate must be greater than 0")
        precondition(burst > 0, "Burst must be greater than 0")
        precondition(period > .zero, "Period must be greater than zero")
        let origin = clock.now
        self.rate = Int128(rate)
        self.tokenCost = period.attoseconds
        self.capacity = period.attoseconds * Int128(burst)
        self.credit = capacity
        self.now = { origin.duration(to: clock.now) }
        self.sleep = { offset in
            try await clock.sleep(until: origin.advanced(by: offset), tolerance: nil)
        }
    }

    /// Creates a full token bucket that refills on the continuous clock.
    /// - Parameters:
    ///   - rate: The number of tokens added per period. Must be greater than 0.
    ///   - period: The time over which `rate` tokens are added. Must be greater than zero.
    ///   - burst: The maximum number of tokens the bucket holds, and the number it starts with. Must be greater than 0.
    public init(rate: Int, per period: Duration, burst: Int) {
        self.init(rate: rate, per: period, burst: burst, clock: ContinuousClock())
    }

    /// Takes one token, waiting in line until one is available.
    ///
    /// A caller that is already cancelled throws without taking a token. Cancellation while
    /// waiting throws `CancellationError` promptly, consumes no token, and leaves the remaining
    /// waiters in order. A cancellation racing with acquisition returns the token before throwing.
    public func acquire() async throws {
        try Task.checkCancellation()
        refill()
        if waiters.isEmpty, credit >= tokenCost {
            credit -= tokenCost
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(Waiter(id: id, continuation: continuation))
                startDraining()
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
        if Task.isCancelled {
            // Cancellation raced with being served: return the token before throwing.
            refill()
            credit += tokenCost
            serveReadyWaiters()
            stopDrainingIfIdle()
            throw CancellationError()
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else {
            return
        }
        // Account for credit accrued while this waiter was queued before removing it.
        refill()
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
        serveReadyWaiters()
        stopDrainingIfIdle()
    }

    /// Returns the number of callers currently waiting for a token.
    public var waitingCount: Int {
        waiters.count
    }

    /// Takes a token for `limited(by:)`, observing cancellation before the limited work starts.
    /// Reports the wait to an enclosing trace exactly as `AsyncSemaphore.withPermit` does.
    func acquireForLimitedWork() async throws {
        await recordOperationTraceEvent(.waitingForPermit)
        do {
            try await acquire()
        } catch {
            await recordOperationTraceEvent(.permitWaitCancelled)
            throw error
        }
        await recordOperationTraceEvent(.acquiredPermit)
        try Task.checkCancellation()
    }

    private func refill() {
        let current = now()
        let elapsed = (current - lastRefill).attoseconds
        guard elapsed > 0 else {
            return
        }
        lastRefill = current
        if waiters.isEmpty, elapsed >= capacity - credit {
            // Since `rate` is at least 1, this fills the bucket; checking first avoids overflow after long idle periods.
            credit = capacity
        } else {
            credit += elapsed * rate
        }
        // Queued waiters take tokens as they accrue, so the cap applies only once none are queued.
        if waiters.isEmpty {
            credit = min(credit, capacity)
        }
    }

    private func serveReadyWaiters() {
        refill()
        while !waiters.isEmpty, credit >= tokenCost {
            credit -= tokenCost
            waiters.removeFirst().continuation.resume()
        }
        credit = min(credit, capacity)
    }

    private func startDraining() {
        guard drainer == nil else {
            return
        }
        drainGeneration += 1
        let generation = drainGeneration
        drainer = Task { await self.drain(generation) }
    }

    /// Keeps a drainer only while waiters are queued, so a new head always starts a drainer with a fresh due time.
    private func stopDrainingIfIdle() {
        guard waiters.isEmpty else {
            return
        }
        drainer?.cancel()
        drainer = nil
    }

    /// Serves waiters in order, sleeping on the clock until the next token is due.
    /// Serving happens synchronously on the actor, so wake-ups after reentrant changes cannot double-serve.
    private func drain(_ generation: Int) async {
        while !Task.isCancelled {
            serveReadyWaiters()
            if waiters.isEmpty {
                break
            }
            // Round up so the sleeper never wakes before the token is complete.
            let wait = (tokenCost - credit + rate - 1) / rate
            try? await sleep(lastRefill + Duration(attoseconds: wait))
        }
        // A drainer stopped by cancellation may finish after its replacement has started.
        if generation == drainGeneration {
            drainer = nil
        }
    }
}
