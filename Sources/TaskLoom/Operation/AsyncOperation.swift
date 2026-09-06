import Foundation

/// A composable, lazy async operation that can be configured with retry, timeout, and other policies.
///
/// `AsyncOperation` wraps an async throwing closure and allows you to chain modifiers
/// to add resilience and control. The operation is lazy - nothing executes until you call `execute()`.
///
/// ```swift
/// // Basic usage with retry and timeout
/// let result = try await AsyncOperation { try await api.fetchUser(id) }
///     .retry(3, backoff: .exponential(base: .milliseconds(100)))
///     .timeout(.seconds(5))
///     .execute()
///
/// // With fallback
/// let config = try await AsyncOperation { try await fetchRemoteConfig() }
///     .timeout(.seconds(2))
///     .fallback { Config.default }
///     .execute()
///
/// // Reusable operation template
/// let fetchUser = AsyncOperation { try await api.fetchUser(id) }
///     .retry(3)
///     .timeout(.seconds(10))
///
/// let user = try await fetchUser.execute()
/// ```
public struct AsyncOperation<Success: Sendable>: Sendable {

    /// The underlying async operation.
    private let operation: @Sendable () async throws -> Success

    /// Creates a new async operation.
    /// - Parameter operation: The async throwing closure to execute.
    public init(_ operation: @escaping @Sendable () async throws -> Success) {
        self.operation = operation
    }

    /// Executes the operation and returns the result.
    /// - Returns: The successful result of the operation.
    /// - Throws: Any error thrown by the operation or its modifiers.
    public func execute() async throws -> Success {
        try await operation()
    }

    // MARK: - Timeout

    /// Adds a timeout to the operation.
    ///
    /// If the operation does not complete within the specified duration,
    /// it will be cancelled and an `AsyncOperationError.timeout` will be thrown.
    /// Cancellation is cooperative: this method waits for the operation to finish
    /// cancelling, so an operation that ignores cancellation can exceed the timeout.
    ///
    /// - Parameter duration: The maximum time to wait for the operation to complete.
    /// - Returns: A new operation with timeout applied.
    public func timeout(_ duration: Duration) -> AsyncOperation<Success> {
        AsyncOperation {
            try await withThrowingTaskGroup(of: Success.self) { group in
                group.addTask {
                    try await self.operation()
                }

                group.addTask {
                    try await Task.sleep(for: duration)
                    throw AsyncOperationError.timeout(duration)
                }

                guard let result = try await group.next() else {
                    throw AsyncOperationError.cancelled
                }

                group.cancelAll()
                return result
            }
        }
    }

    // MARK: - Retry

    /// Adds retry logic to the operation.
    ///
    /// If the operation fails, it will be retried up to the specified number of attempts
    /// with the given backoff strategy between attempts.
    ///
    /// - Parameters:
    ///   - attempts: The maximum number of attempts (including the initial attempt).
    ///   - backoff: The strategy for calculating delay between retries. Defaults to `.none`.
    /// - Returns: A new operation with retry logic applied.
    public func retry(
        _ attempts: Int,
        backoff: BackoffStrategy = .none
    ) -> AsyncOperation<Success> {
        precondition(attempts > 0, "Retry attempts must be greater than 0")

        return AsyncOperation {
            var lastError: (any Error)?

            for attempt in 0 ..< attempts {
                do {
                    return try await self.operation()
                } catch {
                    lastError = error

                    // Don't delay after the last attempt
                    if attempt < attempts - 1 {
                        let delay = backoff.delay(for: attempt)
                        if delay > .zero {
                            try await Task.sleep(for: delay)
                        }
                    }

                    // Check for cancellation between retries
                    try Task.checkCancellation()
                }
            }

            throw AsyncOperationError.maxRetriesExceeded(
                attempts: attempts,
                lastError: lastError ?? AsyncOperationError.cancelled
            )
        }
    }

    // MARK: - Fallback

    /// Provides a fallback value if the operation fails.
    ///
    /// If the primary operation throws an error, the fallback closure will be executed instead.
    ///
    /// - Parameter fallback: A closure that provides the fallback value.
    /// - Returns: A new operation that uses the fallback on failure.
    public func fallback(
        _ fallback: @escaping @Sendable () async throws -> Success
    ) -> AsyncOperation<Success> {
        AsyncOperation {
            do {
                return try await self.operation()
            } catch {
                return try await fallback()
            }
        }
    }

    /// Provides a constant fallback value if the operation fails.
    ///
    /// - Parameter value: The fallback value to use on failure.
    /// - Returns: A new operation that uses the fallback value on failure.
    public func fallback(_ value: Success) -> AsyncOperation<Success> {
        fallback { value }
    }

    // MARK: - Rate Limiting

    /// Limits the operation using a semaphore.
    ///
    /// The operation will wait for a permit from the semaphore before executing,
    /// useful for limiting concurrent operations.
    ///
    /// - Parameter semaphore: The semaphore to use for rate limiting.
    /// - Returns: A new operation that acquires a permit before executing.
    public func limited(by semaphore: AsyncSemaphore) -> AsyncOperation<Success> {
        AsyncOperation {
            try await semaphore.withPermit {
                try await self.operation()
            }
        }
    }

    // MARK: - Lifecycle Hooks

    /// Adds a callback that executes when the operation succeeds.
    ///
    /// - Parameter handler: A closure called with the successful result.
    /// - Returns: A new operation with the success handler attached.
    public func onSuccess(
        _ handler: @escaping @Sendable (Success) async -> Void
    ) -> AsyncOperation<Success> {
        AsyncOperation {
            let result = try await self.operation()
            await handler(result)
            return result
        }
    }

    /// Adds a callback that executes when the operation fails.
    ///
    /// - Parameter handler: A closure called with the error.
    /// - Returns: A new operation with the failure handler attached.
    public func onFailure(
        _ handler: @escaping @Sendable (any Error) async -> Void
    ) -> AsyncOperation<Success> {
        AsyncOperation {
            do {
                return try await self.operation()
            } catch {
                await handler(error)
                throw error
            }
        }
    }

    /// Adds a callback that executes when the operation completes (success or failure).
    ///
    /// - Parameter handler: A closure called with the result.
    /// - Returns: A new operation with the completion handler attached.
    public func onCompletion(
        _ handler: @escaping @Sendable (Result<Success, any Error>) async -> Void
    ) -> AsyncOperation<Success> {
        AsyncOperation {
            do {
                let result = try await self.operation()
                await handler(.success(result))
                return result
            } catch {
                await handler(.failure(error))
                throw error
            }
        }
    }

    // MARK: - Transformation

    /// Transforms the successful result of the operation.
    ///
    /// - Parameter transform: A closure that transforms the result.
    /// - Returns: A new operation with the transformed result type.
    public func map<NewSuccess: Sendable>(
        _ transform: @escaping @Sendable (Success) async throws -> NewSuccess
    ) -> AsyncOperation<NewSuccess> {
        AsyncOperation<NewSuccess> {
            try await transform(self.operation())
        }
    }

    /// Chains another operation that depends on the result of this one.
    ///
    /// - Parameter transform: A closure that takes the result and returns a new operation.
    /// - Returns: A new operation representing the chained operations.
    public func flatMap<NewSuccess: Sendable>(
        _ transform: @escaping @Sendable (Success) async throws -> AsyncOperation<NewSuccess>
    ) -> AsyncOperation<NewSuccess> {
        AsyncOperation<NewSuccess> {
            let intermediate = try await self.operation()
            return try await transform(intermediate).execute()
        }
    }

    // MARK: - Cancellation

    /// Checks for cancellation before executing the operation.
    ///
    /// - Returns: A new operation that throws `CancellationError` if cancelled.
    public func checkCancellation() -> AsyncOperation<Success> {
        AsyncOperation {
            try Task.checkCancellation()
            return try await self.operation()
        }
    }
}

// MARK: - Convenience Initializers

public extension AsyncOperation {
    /// Creates an operation from a non-throwing async closure.
    ///
    /// - Parameter operation: The async closure to execute.
    init(_ operation: @escaping @Sendable () async -> Success) {
        self.operation = operation
    }

    /// Creates an operation that immediately succeeds with the given value.
    ///
    /// - Parameter value: The value to return.
    static func just(_ value: Success) -> AsyncOperation<Success> {
        AsyncOperation { value }
    }

    /// Creates an operation that immediately fails with the given error.
    ///
    /// - Parameter error: The error to throw.
    static func fail(_ error: any Error) -> AsyncOperation<Success> {
        AsyncOperation { throw error }
    }
}

// MARK: - Race & Combine

public extension AsyncOperation {
    /// Races multiple operations and returns the result of the first to complete.
    ///
    /// The first completion wins, including a thrown error. Remaining operations
    /// are cancelled, and the task group waits for their cooperative termination.
    ///
    /// - Parameter operations: The operations to race.
    /// - Returns: An operation that returns or throws the first completed result.
    static func race(_ operations: [AsyncOperation<Success>]) -> AsyncOperation<Success> {
        precondition(!operations.isEmpty, "Cannot race zero operations")

        return AsyncOperation {
            try await withThrowingTaskGroup(of: Success.self) { group in
                for operation in operations {
                    group.addTask {
                        try await operation.execute()
                    }
                }

                guard let result = try await group.next() else {
                    throw AsyncOperationError.cancelled
                }

                group.cancelAll()
                return result
            }
        }
    }

    /// Races this operation against another and returns the first to complete.
    ///
    /// - Parameter other: The operation to race against.
    /// - Returns: An operation that returns or throws the first completed result.
    func race(against other: AsyncOperation<Success>) -> AsyncOperation<Success> {
        AsyncOperation.race([self, other])
    }
}

// MARK: - Collecting Results

public extension AsyncOperation {
    /// Executes multiple operations concurrently and collects all results.
    ///
    /// - Parameter operations: The operations to execute.
    /// - Returns: An operation that returns all results in order.
    static func all(_ operations: [AsyncOperation<Success>]) -> AsyncOperation<[Success]> {
        AsyncOperation<[Success]> {
            try await withThrowingTaskGroup(of: (Int, Success).self) { group in
                for (index, operation) in operations.enumerated() {
                    group.addTask {
                        (index, try await operation.execute())
                    }
                }

                var results = [(Int, Success)]()
                results.reserveCapacity(operations.count)

                for try await result in group {
                    results.append(result)
                }

                return results.sorted { $0.0 < $1.0 }.map(\.1)
            }
        }
    }

    /// Executes multiple operations concurrently, collecting successes and ignoring failures.
    ///
    /// - Parameter operations: The operations to execute.
    /// - Returns: An operation that returns all successful results.
    static func allSettled(_ operations: [AsyncOperation<Success>]) -> AsyncOperation<[Success]> {
        AsyncOperation<[Success]> {
            await withTaskGroup(of: (Int, Success?).self) { group in
                for (index, operation) in operations.enumerated() {
                    group.addTask {
                        (index, try? await operation.execute())
                    }
                }

                var results = [(Int, Success)]()
                results.reserveCapacity(operations.count)

                for await result in group {
                    if let value = result.1 {
                        results.append((result.0, value))
                    }
                }

                return results.sorted { $0.0 < $1.0 }.map(\.1)
            }
        }
    }
}

// MARK: - Tracing

public extension AsyncOperation {
    /// Returns an operation with the same execution behavior.
    ///
    /// - Parameters:
    ///   - file: The source file.
    ///   - function: The function name.
    ///   - line: The line number.
    /// - Returns: A new operation with tracing enabled.
    func traced(
        _ file: String = #file,
        _ function: String = #function,
        _ line: UInt = #line
    ) -> AsyncOperation<Success> {
        AsyncOperation {
            do {
                return try await self.operation()
            } catch {
                throw error
            }
        }
    }
}
