import Foundation
import Synchronization

/// A clock advanced explicitly by tests. Advancing resumes currently due sleepers;
/// use `waitUntilSleeping(count:)` before advancing to synchronize with new work.
public final class ManualClock: Clock, Sendable {
    public struct Instant: InstantProtocol, Sendable {
        public let offset: Swift.Duration

        public init(offset: Swift.Duration = .zero) {
            self.offset = offset
        }

        public func advanced(by duration: Swift.Duration) -> Self {
            Self(offset: offset + duration)
        }

        public func duration(to other: Self) -> Swift.Duration {
            other.offset - offset
        }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private struct Sleeper: Sendable {
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct Observer: Sendable {
        let count: Int
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State: Sendable {
        var now = Instant()
        var sleepers: [UUID: Sleeper] = [:]
        var observers: [UUID: Observer] = [:]
    }

    private let state = Mutex(State())

    public init() {}
    public var now: Instant {
        state.withLock { $0.now }
    }

    public var minimumResolution: Swift.Duration {
        .nanoseconds(1)
    }

    public var sleepingCount: Int {
        state.withLock { $0.sleepers.count }
    }

    public func sleep(until deadline: Instant, tolerance: Swift.Duration? = nil) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                state.withLock { state in
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else if deadline <= state.now {
                        continuation.resume()
                    } else {
                        state.sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
                        let ready = state.observers.filter { $0.value.count <= state.sleepers.count }
                        for (key, observer) in ready {
                            state.observers.removeValue(forKey: key)
                            observer.continuation.resume()
                        }
                    }
                }
            }
        } onCancel: {
            self.state.withLock { state in
                state.sleepers.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
            }
        }
        try Task.checkCancellation()
    }

    /// Advances monotonically and resumes sleepers whose deadlines have passed.
    /// Does not wait for resumed tasks to finish or register their next sleep.
    public func advance(by duration: Swift.Duration) {
        precondition(duration >= .zero, "A clock cannot advance backwards")
        state.withLock { state in
            state.now = state.now.advanced(by: duration)
            let ready = state.sleepers.filter { $0.value.deadline <= state.now }
            for (key, sleeper) in ready {
                state.sleepers.removeValue(forKey: key)
                sleeper.continuation.resume()
            }
        }
    }

    /// Suspends until at least `count` sleeps are registered. Supports cancellation.
    public func waitUntilSleeping(count: Int = 1) async throws {
        precondition(count >= 0, "Sleeper count must be nonnegative")
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                state.withLock { state in
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else if state.sleepers.count >= count {
                        continuation.resume()
                    } else {
                        state.observers[id] = Observer(count: count, continuation: continuation)
                    }
                }
            }
        } onCancel: {
            self.state.withLock { state in
                state.observers.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
            }
        }
        try Task.checkCancellation()
    }
}
