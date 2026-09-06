import Foundation
import Logging

/// Creates and runs a repeating task on the main actor
/// - Parameters:
///   - priority: Task priority level (default: .low)
///   - interval: Time in seconds to wait between iterations (default: 0)
///   - file: Source file where task is created (default: current file)
///   - functionName: Function where task is created (default: current function)
///   - line: Line number where task is created (default: current line)
///   - handler: The async closure to execute repeatedly. Returns bool indicating whether to continue repeating.
/// - Returns: A Task handle that can be cancelled
@discardableResult public func RepeatingTask(
    priority: TaskPriority = .low,
    interval: TimeInterval = 0,
    _ file: String = #file,
    _ functionName: String = #function,
    _ line: UInt = #line,
    _ handler: @MainActor @Sendable @escaping () async -> Bool
) -> _Concurrency.Task<Void, Never> {
    RepeatingTask(priority: priority, interval: .seconds(interval), clock: ContinuousClock(), file, functionName, line, handler)
}

/// Repeats a main-actor handler, waiting on the clock before each iteration.
/// Returns when the handler returns false, sleeping fails, or the task is cancelled.
@discardableResult public func RepeatingTask<C: Clock>(
    priority: TaskPriority = .low,
    interval: Duration = .zero,
    clock: C,
    _ file: String = #file,
    _ functionName: String = #function,
    _ line: UInt = #line,
    _ handler: @MainActor @Sendable @escaping () async -> Bool
) -> Task<Void, Never> where C.Duration == Duration {
    Task(priority: priority) { @MainActor in
        do {
            while !Task.isCancelled {
                if interval > .zero { try await clock.sleep(for: interval) }
                try Task.checkCancellation()
                if !(await handler()) { return }
            }
        } catch is CancellationError {
            // Cancellation is an expected way to stop repeating.
        } catch {
            taskLoomLogger.error("\(error)")
        }
    }
}
