import Foundation
import Logging

/// Creates and runs a delayed task on the main actor that does not throw errors
/// - Parameters:
///   - priority: Task priority level (default: .medium)
///   - delay: Time in seconds to wait before executing the task (default: 0)
///   - file: Source file where task is created (default: current file)
///   - functionName: Function where task is created (default: current function)
///   - line: Line number where task is created (default: current line)
///   - handler: The async closure to execute after the delay
/// - Returns: A Task handle that can be cancelled
@discardableResult public func DelayedTask(
    priority: TaskPriority = .medium,
    delay: TimeInterval = 0,
    _ file: String = #file,
    _ functionName: String = #function,
    _ line: UInt = #line,
    _ handler: @MainActor @Sendable @escaping () async -> Void
) -> _Concurrency.Task<Void, Never> {
    DelayedTask(priority: priority, delay: .seconds(delay), clock: ContinuousClock(), file, functionName, line, handler)
}

/// Creates and runs a delayed task on the main actor that can throw errors
/// - Parameters:
///   - priority: Task priority level (default: .medium)
///   - delay: Time in seconds to wait before executing the task (default: 0)
///   - file: Source file where task is created (default: current file)
///   - functionName: Function where task is created (default: current function)
///   - line: Line number where task is created (default: current line)
///   - handler: The async throwing closure to execute after the delay
/// - Returns: A Task handle that can be cancelled
/// - Throws: Rethrows any error thrown by the handler
@discardableResult public func DelayedTask(
    priority: TaskPriority = .medium,
    delay: TimeInterval = 0,
    _ file: String = #file,
    _ functionName: String = #function,
    _ line: UInt = #line,
    _ handler: @MainActor @Sendable @escaping () async throws -> Void
) -> _Concurrency.Task<Void, any Error> {
    DelayedTask(priority: priority, delay: .seconds(delay), clock: ContinuousClock(), file, functionName, line, handler)
}

/// Runs a main-actor handler after a delay measured by the supplied clock.
/// Cancellation during the delay prevents the handler from running.
@discardableResult public func DelayedTask<C: Clock>(
    priority: TaskPriority = .medium,
    delay: Duration = .zero,
    clock: C,
    _ file: String = #file,
    _ functionName: String = #function,
    _ line: UInt = #line,
    _ handler: @MainActor @Sendable @escaping () async -> Void
) -> Task<Void, Never> where C.Duration == Duration {
    Task(priority: priority) { @MainActor in
        do {
            if delay > .zero {
                try await clock.sleep(for: delay)
            }
            try Task.checkCancellation()
            await handler()
        } catch is CancellationError {
            // Cancellation is an expected way to stop a delayed task.
        } catch {
            taskLoomLogger.error("\(error)")
        }
    }
}

/// Runs a throwing main-actor handler after a delay measured by the supplied clock.
/// Cancellation during the delay throws `CancellationError`.
@discardableResult public func DelayedTask<C: Clock>(
    priority: TaskPriority = .medium,
    delay: Duration = .zero,
    clock: C,
    _ file: String = #file,
    _ functionName: String = #function,
    _ line: UInt = #line,
    _ handler: @MainActor @Sendable @escaping () async throws -> Void
) -> Task<Void, any Error> where C.Duration == Duration {
    Task(priority: priority) { @MainActor in
        if delay > .zero {
            try await clock.sleep(for: delay)
        }
        try Task.checkCancellation()
        try await handler()
    }
}
