/// Runs asynchronous operations one at a time, in the order they are enqueued.
///
/// Each call to ``enqueue(_:)`` suspends until every operation enqueued before it
/// has finished, runs its own operation, and returns that operation's value or
/// rethrows its error.
///
/// ```swift
/// let queue = AsyncOperationSerialQueue(name: "Database writes")
///
/// let saved = try await queue.enqueue {
///     try await database.save(record)
/// }
///
/// // Fire-and-forget: wrap the call in a task.
/// Task { try await queue.enqueue { try await database.save(other) } }
/// ```
///
/// ## Ordering
///
/// Operations run in the order their ``enqueue(_:)`` calls reach the queue.
/// Calls made one after another from the same isolation context, such as the
/// main actor or a single task, reach the queue in call order. Calls from
/// different tasks or isolation domains race, and their relative order is not
/// defined.
///
/// ## Cancellation
///
/// - If a caller is cancelled before its operation starts, the operation never
///   runs and the caller throws `CancellationError` immediately, without waiting
///   for the running operation.
/// - If a caller is cancelled while its operation runs, the operation's task is
///   cancelled. Cancellation is cooperative: the caller receives whatever the
///   operation returns or throws, and the next operation starts only after it
///   finishes.
/// - ``cancelAll()`` applies both rules to every caller at once.
///
/// ## Reentrancy
///
/// An operation must not enqueue onto the queue that is running it: the inner call
/// would wait for the outer operation, which is waiting for the inner call. The
/// queue detects this with a task-local value and stops with a precondition
/// failure. Unstructured tasks created inside an operation inherit task-local
/// values, so they are treated the same way; use `Task.detached` to schedule
/// follow-up work on the same queue. Enqueuing onto a different queue is allowed.
public actor AsyncOperationSerialQueue {
    private struct Waiter {
        let id: UInt64
        let continuation: CheckedContinuation<Void, any Error>
    }

    /// The caller that currently owns the queue.
    private struct Turn {
        var isCancelled = false
        var cancelOperation: (@Sendable () -> Void)?
    }

    /// The queues whose operations the current task is running inside.
    @TaskLocal private static var runningQueues: Set<ObjectIdentifier> = []

    /// A descriptive name for the queue, included in diagnostics.
    public let name: String

    private var turn: Turn?
    private var waiters: [Waiter] = []
    private var nextWaiterID: UInt64 = 0

    /// Creates an empty queue.
    /// - Parameter name: A descriptive name for the queue, included in diagnostics.
    public init(name: String) {
        self.name = name
    }

    /// Runs `operation` after every operation enqueued before it has finished.
    ///
    /// The operation runs in a new task that inherits the caller's priority and
    /// task-local values. It is not forced onto any actor; pass a `@MainActor`
    /// closure to run it on the main actor.
    ///
    /// Calling this method from inside an operation running on the same queue is a
    /// programming error and stops with a precondition failure.
    ///
    /// - Parameter operation: The work to run once it is this caller's turn.
    /// - Returns: The value returned by `operation`.
    /// - Throws: The error thrown by `operation`, or `CancellationError` if the
    ///   caller is cancelled, or ``cancelAll()`` is called, before the operation starts.
    public func enqueue<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let queueID = ObjectIdentifier(self)
        let runningQueues = Self.runningQueues
        precondition(
            !runningQueues.contains(queueID),
            """
            AsyncOperationSerialQueue "\(name)": enqueue(_:) was called from inside an operation running on \
            this same queue. The call would wait for the operation that made it and never return.
            """
        )
        try await waitForTurn()
        defer { finishTurn() }
        // A caller cancelled, or swept by cancelAll(), as its turn was granted skips its operation.
        guard !Task.isCancelled, turn?.isCancelled == false else {
            throw CancellationError()
        }
        let task = Task {
            try await Self.$runningQueues.withValue(runningQueues.union([queueID])) {
                try await operation()
            }
        }
        turn?.cancelOperation = { task.cancel() }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Fails every caller still waiting for its turn with `CancellationError` and
    /// cancels the running operation.
    ///
    /// The running operation stops only if it cooperates with cancellation, and its
    /// caller receives whatever it returns or throws. The queue stays usable:
    /// operations enqueued afterwards run once the running operation has finished.
    public func cancelAll() {
        let cancelled = waiters
        waiters.removeAll()
        turn?.isCancelled = true
        turn?.cancelOperation?()
        for waiter in cancelled {
            waiter.continuation.resume(throwing: CancellationError())
        }
    }

    private func waitForTurn() async throws {
        try Task.checkCancellation()
        guard turn != nil else {
            turn = Turn()
            return
        }
        let id = nextWaiterID
        nextWaiterID += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UInt64) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else {
            return
        }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    /// Hands the queue to the next waiter, or marks it idle.
    private func finishTurn() {
        guard !waiters.isEmpty else {
            turn = nil
            return
        }
        turn = Turn()
        waiters.removeFirst().continuation.resume()
    }

    /// Whether a caller owns the queue.
    var isBusy: Bool {
        turn != nil
    }

    /// The number of callers waiting for their turn.
    var waitingCount: Int {
        waiters.count
    }
}
