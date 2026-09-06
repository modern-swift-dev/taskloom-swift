import Foundation

/// A composable, lazy async task that cannot fail.
///
/// `AsyncTask` is the non-throwing counterpart to `AsyncOperation`. Use it when your
/// async work cannot fail, or when you want to handle errors internally and provide defaults.
///
/// ```swift
/// // Basic usage
/// let result = await AsyncTask { await computeValue() }
///     .timeout(.seconds(5), default: .defaultValue)
///     .execute()
///
/// // Convert from AsyncOperation with fallback
/// let task = AsyncOperation { try await fetchConfig() }
///     .toTask(default: Config.default)
/// ```
public struct AsyncTask<Success: Sendable>: Sendable {

    /// The underlying async task.
    private let task: @Sendable () async -> Success

    /// Creates a new async task.
    /// - Parameter task: The async closure to execute.
    public init(_ task: @escaping @Sendable () async -> Success) {
        self.task = task
    }

    /// Executes the task and returns the result.
    /// - Returns: The result of the task.
    public func execute() async -> Success {
        await task()
    }

    // MARK: - Timeout

    /// Adds a timeout to the task with a default value.
    ///
    /// If the task does not complete within the specified duration,
    /// it will be cancelled and the default value will be returned.
    ///
    /// - Parameters:
    ///   - duration: The maximum time to wait for the task to complete.
    ///   - defaultValue: The value to return if the timeout is reached.
    /// - Returns: A new task with timeout applied.
    public func timeout(_ duration: Duration, default defaultValue: Success) -> AsyncTask<Success> {
        AsyncTask {
            await withTaskGroup(of: Success?.self) { group in
                group.addTask {
                    await self.task()
                }

                group.addTask {
                    try? await Task.sleep(for: duration)
                    return nil
                }

                if let result = await group.next(), let value = result {
                    group.cancelAll()
                    return value
                }

                group.cancelAll()
                return defaultValue
            }
        }
    }

    // MARK: - Rate Limiting

    /// Limits the task using a semaphore.
    ///
    /// - Parameter semaphore: The semaphore to use for rate limiting.
    /// - Returns: A new task that acquires a permit before executing.
    public func limited(by semaphore: AsyncSemaphore) -> AsyncTask<Success> {
        AsyncTask {
            await semaphore.withPermit {
                await self.task()
            }
        }
    }

    // MARK: - Lifecycle Hooks

    /// Adds a callback that executes when the task completes.
    ///
    /// - Parameter handler: A closure called with the result.
    /// - Returns: A new task with the completion handler attached.
    public func onComplete(
        _ handler: @escaping @Sendable (Success) async -> Void
    ) -> AsyncTask<Success> {
        AsyncTask {
            let result = await self.task()
            await handler(result)
            return result
        }
    }

    // MARK: - Transformation

    /// Transforms the result of the task.
    ///
    /// - Parameter transform: A closure that transforms the result.
    /// - Returns: A new task with the transformed result type.
    public func map<NewSuccess: Sendable>(
        _ transform: @escaping @Sendable (Success) async -> NewSuccess
    ) -> AsyncTask<NewSuccess> {
        AsyncTask<NewSuccess> {
            await transform(self.task())
        }
    }

    /// Chains another task that depends on the result of this one.
    ///
    /// - Parameter transform: A closure that takes the result and returns a new task.
    /// - Returns: A new task representing the chained tasks.
    public func flatMap<NewSuccess: Sendable>(
        _ transform: @escaping @Sendable (Success) async -> AsyncTask<NewSuccess>
    ) -> AsyncTask<NewSuccess> {
        AsyncTask<NewSuccess> {
            let intermediate = await self.task()
            return await transform(intermediate).execute()
        }
    }

    // MARK: - Conversion

    /// Converts this task to a throwing operation.
    ///
    /// - Returns: An `AsyncOperation` that wraps this task.
    public func toOperation() -> AsyncOperation<Success> {
        AsyncOperation { await self.task() }
    }
}

// MARK: - Convenience Initializers

public extension AsyncTask {
    /// Creates a task that immediately returns the given value.
    ///
    /// - Parameter value: The value to return.
    static func just(_ value: Success) -> AsyncTask<Success> {
        AsyncTask { value }
    }
}

// MARK: - Race & Combine

public extension AsyncTask {
    /// Races multiple tasks and returns the result of the first to complete.
    ///
    /// - Parameter tasks: The tasks to race.
    /// - Returns: A task that returns the first result.
    static func race(_ tasks: [AsyncTask<Success>]) -> AsyncTask<Success> {
        precondition(!tasks.isEmpty, "Cannot race zero tasks")

        return AsyncTask {
            await withTaskGroup(of: Success.self) { group in
                for task in tasks {
                    group.addTask {
                        await task.execute()
                    }
                }

                // Safe to force unwrap since we verified tasks is not empty
                let result = await group.next()!
                group.cancelAll()
                return result
            }
        }
    }

    /// Executes multiple tasks concurrently and collects all results.
    ///
    /// - Parameter tasks: The tasks to execute.
    /// - Returns: A task that returns all results in order.
    static func all(_ tasks: [AsyncTask<Success>]) -> AsyncTask<[Success]> {
        AsyncTask<[Success]> {
            await withTaskGroup(of: (Int, Success).self) { group in
                for (index, task) in tasks.enumerated() {
                    group.addTask {
                        (index, await task.execute())
                    }
                }

                var results = [(Int, Success)]()
                results.reserveCapacity(tasks.count)

                for await result in group {
                    results.append(result)
                }

                return results.sorted { $0.0 < $1.0 }.map(\.1)
            }
        }
    }
}

// MARK: - AsyncOperation Conversion

public extension AsyncOperation {
    /// Converts this operation to a non-throwing task with a default value.
    ///
    /// If the operation fails, the default value will be returned.
    ///
    /// - Parameter defaultValue: The value to return on failure.
    /// - Returns: An `AsyncTask` that cannot fail.
    func toTask(default defaultValue: Success) -> AsyncTask<Success> {
        AsyncTask {
            (try? await self.execute()) ?? defaultValue
        }
    }

    /// Converts this operation to a non-throwing task with a default closure.
    ///
    /// If the operation fails, the default closure will be executed.
    ///
    /// - Parameter defaultValue: A closure that provides the default value.
    /// - Returns: An `AsyncTask` that cannot fail.
    func toTask(
        default defaultValue: @escaping @Sendable () async -> Success
    ) -> AsyncTask<Success> {
        AsyncTask {
            do {
                return try await self.execute()
            } catch {
                return await defaultValue()
            }
        }
    }
}
