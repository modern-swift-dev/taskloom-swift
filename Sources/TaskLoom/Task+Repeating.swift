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
    return Task(priority: priority) { @MainActor in
        do {
            var shouldContinue = true
            while shouldContinue, !Task.isCancelled {
                if interval > 0 {
                    try await Task.sleep(for: .seconds(interval))
                }

                if !Task.isCancelled {
                    shouldContinue = await handler()
                }
            }
        } catch {
            taskLoomLogger.error("\(error)")
        }
    }
}
