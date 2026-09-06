import Foundation

public typealias UITaskCallback = @MainActor @Sendable () -> Void
public typealias UITaskAsyncCallback = @MainActor @Sendable () async -> Void

/// Creates and runs a task on the main actor that does not throw errors
/// - Parameters:
///   - priority: Task priority level (default: .medium)
///   - file: Source file where task is created (default: current file)
///   - functionName: Function where task is created (default: current function)
///   - line: Line number where task is created (default: current line)
///   - handler: The async closure to execute on the main actor
/// - Returns: A Task handle that can be cancelled
@discardableResult public func UITask(
    _ priority: TaskPriority = .medium,
    _ file: String = #file,
    _ functionName: String = #function,
    _ line: UInt = #line,
    _ handler: @escaping UITaskAsyncCallback
) -> _Concurrency.Task<Void, Never> {
    Task(priority: priority) { @MainActor in
        await handler()
    }
}
