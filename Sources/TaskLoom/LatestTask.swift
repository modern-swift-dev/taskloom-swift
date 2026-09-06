/// Coordinates requests whose results update state on the main actor.
///
/// Submitting a request cancels the previous one. Only the current request can
/// deliver its result, even if earlier work ignores cancellation. Delivery is
/// synchronous on the main actor so replacement cannot interleave between the
/// current-request check and the state update.
@MainActor
public final class LatestTask {
    private final class Generation: Sendable {}
    private var generation: Generation?
    private var task: Task<Void, Never>?

    /// Whether the current request is still running.
    public var isRunning: Bool { task != nil }

    public init() {}

    deinit {
        task?.cancel()
    }

    /// Replaces the current request and delivers its success or failure.
    ///
    /// Cancellation errors and results from cancelled or superseded requests are
    /// not delivered. The operation must cooperate with cancellation to stop its
    /// work promptly. The returned handle can be awaited to observe completion.
    /// Avoid capturing this coordinator strongly in long-running operations.
    @discardableResult
    public func submit<Output: Sendable>(
        operation: @escaping @Sendable () async throws -> Output,
        onCompletion: @escaping @MainActor @Sendable (Result<Output, any Error>) -> Void
    ) -> Task<Void, Never> {
        cancel()
        let generation = Generation()
        self.generation = generation
        let task = Task { @MainActor [weak self] in
            let result: Result<Output, any Error>
            do {
                try Task.checkCancellation()
                result = .success(try await operation())
            } catch {
                result = .failure(error)
            }

            guard let self, self.generation === generation else { return }
            self.task = nil
            self.generation = nil
            guard !Task.isCancelled else { return }
            if case .failure(let error) = result, error is CancellationError { return }
            onCompletion(result)
        }
        self.task = task
        return task
    }

    /// Invalidates pending delivery and requests cancellation of the current work.
    public func cancel() {
        generation = nil
        task?.cancel()
        task = nil
    }
}
