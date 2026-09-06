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
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }

    private var waiters: [Waiter] = []

    /// Creates a new semaphore with the specified limit.
    /// - Parameter limit: The maximum number of concurrent permits. Must be greater than 0.
    public init(limit: Int) {
        precondition(limit > 0, "Semaphore limit must be greater than 0")
        self.limit = limit
        self.availablePermits = limit
    }

    /// Acquires a permit, throwing when the caller is cancelled while waiting.
    /// A cancellation racing with acquisition returns the permit before throwing.
    public func wait() async throws {
        try Task.checkCancellation()
        if availablePermits > 0 {
            availablePermits -= 1
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
        if Task.isCancelled {
            signal()
            throw CancellationError()
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else {
            return
        }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    /// Executes work with a permit, observing cancellation before starting work.
    /// The permit is released on success, failure, or cancellation of the work.
    public func withPermit<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        await recordOperationTraceEvent(.waitingForPermit)
        do {
            try await wait()
        } catch {
            await recordOperationTraceEvent(.permitWaitCancelled)
            throw error
        }
        defer { signal() }
        await recordOperationTraceEvent(.acquiredPermit)
        try Task.checkCancellation()
        return try await operation()
    }

    /// Releases a permit, potentially allowing a waiting task to proceed.
    ///
    /// If there are tasks waiting for a permit, the first one in line will be resumed.
    /// Otherwise, the available permit count is incremented.
    public func signal() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.continuation.resume()
        } else {
            availablePermits = min(availablePermits + 1, limit)
        }
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
