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
    return Task(priority: priority) { @MainActor in
        if delay > 0 {
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                taskLoomLogger.error("\(error)")
            }
        }

        if !Task.isCancelled {
            await handler()
        }
    }
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
    return Task(priority: priority) { @MainActor in
        do {
            if delay > 0 {
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    taskLoomLogger.error("\(error)")
                }
            }

            if !Task.isCancelled {
                try await handler()
            }
        } catch {
            taskLoomLogger.error("\(error)")
            throw error
        }
    }
}
