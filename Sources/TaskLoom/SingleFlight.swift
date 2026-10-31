import Foundation

/// Deduplicates concurrent work by key so callers share one in-progress execution.
///
/// The first caller for a key starts a *flight*; callers that arrive while it is
/// running wait for the same result instead of running their own operation.
///
/// ```swift
/// let profiles = SingleFlight<User.ID, Profile>()
///
/// let profile = try await profiles.run(key: userID) {
///     try await api.fetchProfile(userID)
/// }
/// ```
///
/// When the flight finishes, every caller still waiting receives the same value
/// or the same error and the key is cleared. Nothing is cached: the next call
/// for that key starts a new flight. Different keys run independently.
public actor SingleFlight<Key: Hashable & Sendable, Value: Sendable> {
    private struct Flight {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<Value, any Error>]
    }

    private var flights: [Key: Flight] = [:]

    /// Creates an instance with no flights in progress.
    public init() {}

    /// Returns the result of the flight for `key`, starting one with `operation` if none is running.
    ///
    /// If a flight for `key` is already running, `operation` is not called and this
    /// caller waits for that flight's value or error.
    ///
    /// Cancelling a caller makes it throw `CancellationError` immediately without
    /// affecting other callers. The flight's work is cancelled only once every
    /// waiting caller has cancelled; the key is then cleared so the next call starts
    /// a new flight. The operation must cooperate with cancellation to stop promptly.
    ///
    /// - Parameters:
    ///   - key: Identifies the work to share.
    ///   - operation: The work to run when no flight for `key` is in progress.
    /// - Returns: The value produced by the flight.
    /// - Throws: The flight's error, or `CancellationError` if this caller is cancelled.
    public func run(
        key: Key,
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                join(key: key, waiterID: waiterID, continuation: continuation, operation: operation)
            }
        } onCancel: {
            Task { await self.cancelWaiter(waiterID, key: key) }
        }
    }

    private func join(
        key: Key,
        waiterID: UUID,
        continuation: CheckedContinuation<Value, any Error>,
        operation: @escaping @Sendable () async throws -> Value
    ) {
        // A caller cancelled before registering never joins or starts a flight.
        guard !Task.isCancelled else {
            continuation.resume(throwing: CancellationError())
            return
        }
        if flights[key] != nil {
            flights[key]?.waiters[waiterID] = continuation
            return
        }
        let flightID = UUID()
        let task = Task {
            let result: Result<Value, any Error>
            do {
                result = try .success(await operation())
            } catch {
                result = .failure(error)
            }
            finish(key: key, flightID: flightID, result: result)
        }
        flights[key] = Flight(id: flightID, task: task, waiters: [waiterID: continuation])
    }

    private func finish(key: Key, flightID: UUID, result: Result<Value, any Error>) {
        // A cancelled flight may finish after a newer flight for the same key started.
        guard flights[key]?.id == flightID, let flight = flights.removeValue(forKey: key) else {
            return
        }
        for continuation in flight.waiters.values {
            continuation.resume(with: result)
        }
    }

    private func cancelWaiter(_ waiterID: UUID, key: Key) {
        guard let continuation = flights[key]?.waiters.removeValue(forKey: waiterID) else {
            return
        }
        continuation.resume(throwing: CancellationError())
        if flights[key]?.waiters.isEmpty == true {
            flights.removeValue(forKey: key)?.task.cancel()
        }
    }

    /// The number of callers waiting on the flight for `key`, or `nil` when none is in progress.
    func waiterCount(for key: Key) -> Int? {
        flights[key]?.waiters.count
    }
}
