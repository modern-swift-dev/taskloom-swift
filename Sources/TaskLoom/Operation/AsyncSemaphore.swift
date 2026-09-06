import Foundation

/// An actor-based semaphore for limiting concurrent access to a resource.
///
/// Use `AsyncSemaphore` to control the number of concurrent operations,
/// such as limiting parallel network requests or database connections.
///
/// ```swift
/// let semaphore = AsyncSemaphore(limit: 3)
///
/// // Using withPermit (recommended)
/// let result = try await semaphore.withPermit {
///     try await fetchData()
/// }
///
/// ```
public actor AsyncSemaphore {

    /// The maximum number of concurrent permits.
    public let limit: Int

    /// The current number of available permits.
    public private(set) var availablePermits: Int

    /// Continuations waiting for a permit.
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Creates a new semaphore with the specified limit.
    /// - Parameter limit: The maximum number of concurrent permits. Must be greater than 0.
    public init(limit: Int) {
        precondition(limit > 0, "Semaphore limit must be greater than 0")
        self.limit = limit
        self.availablePermits = limit
    }

    /// Waits until a permit is available, then acquires it.
    ///
    /// If a permit is immediately available, this method returns without suspending.
    /// Otherwise, it suspends until a permit becomes available via `signal()`.
    /// Waiting does not observe task cancellation; a cancelled waiter still needs
    /// a permit to resume. Prefer `withPermit` to ensure the permit is released.
    public func wait() async {
        if availablePermits > 0 {
            availablePermits -= 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Releases a permit, potentially allowing a waiting task to proceed.
    ///
    /// If there are tasks waiting for a permit, the first one in line will be resumed.
    /// Otherwise, the available permit count is incremented.
    public func signal() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            availablePermits = min(availablePermits + 1, limit)
        }
    }

    /// Executes an operation while holding a permit.
    ///
    /// This method automatically acquires a permit before executing the operation
    /// and releases it afterward, even if the operation throws an error.
    ///
    /// - Parameter operation: The async operation to execute.
    /// - Returns: The result of the operation.
    /// - Throws: Rethrows any error from the operation.
    public func withPermit<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async rethrows -> T {
        await wait()
        defer { signal() }
        return try await operation()
    }

    /// Executes a non-throwing operation while holding a permit.
    ///
    /// - Parameter operation: The async operation to execute.
    /// - Returns: The result of the operation.
    public func withPermit<T: Sendable>(
        _ operation: @Sendable () async -> T
    ) async -> T {
        await wait()
        defer { signal() }
        return await operation()
    }

    /// Returns whether the semaphore has available permits without blocking.
    public var hasAvailablePermits: Bool {
        availablePermits > 0
    }

    /// Returns the number of tasks currently waiting for a permit.
    public var waitingCount: Int {
        waiters.count
    }
}
