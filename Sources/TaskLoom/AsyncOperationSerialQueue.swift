#if canImport(Combine)
    import Combine
    import Foundation
    import Logging
    import Synchronization

    /// An async-await serial queue backed by an AsyncStream.
    /// This class provides a mechanism to execute asynchronous operations serially, ensuring that
    /// only one operation runs at a time, in submission order. It also offers cancellation capabilities and tracks progress.
    /// Submissions are buffered before the enqueue method returns. Concurrent callers are ordered
    /// by acquisition of the queue's state lock.
    ///
    /// Thread Safety: Marked `@unchecked Sendable` because:
    /// - `name` is immutable (`let`)
    /// - `continuation` (AsyncStream.Continuation) is internally thread-safe
    /// - `progress` is an immutable reference to Foundation's thread-safe `Progress`
    /// - `state` uses `Mutex` for the consumer task, cancellation and flush continuations
    public class AsyncOperationSerialQueue: Cancellable, @unchecked Sendable {

        private struct FlushWaiter {
            let id: UUID
            let continuation: CheckedContinuation<Void, Never>
        }

        private struct State {
            var isCancelled = false
            var flushWaiters: [FlushWaiter] = []
            var task: Task<Void, Never>?
        }

        /// Represents a single serial task within the queue.
        /// It holds information about the task, its origin, and its cancellation status.
        ///
        /// Thread Safety: Marked `@unchecked Sendable` because:
        /// - All properties except `_isCancelled` are immutable (`let`)
        /// - `_isCancelled` uses `Atomic<Bool>` for thread-safe access
        final class SerialTask: Cancellable, @unchecked Sendable, CustomDebugStringConvertible, CustomStringConvertible {

            /// The name of the owner/queue that created this task.
            let owner: String
            /// A unique identifier for the task.
            let id: UUID
            /// The creation date of the task.
            let created: Date
            private let createdInstant = ContinuousClock.now
            /// The file name where the task was enqueued.
            let file: String
            /// The function name where the task was enqueued.
            let functionName: String
            /// The line number where the task was enqueued.
            let line: UInt
            /// Thread-safe storage for the cancellation flag.
            private let _isCancelled = Atomic<Bool>(false)
            /// A boolean indicating if the task has been cancelled.
            var isCancelled: Bool {
                _isCancelled.load(ordering: .acquiring)
            }

            /// The actual asynchronous operation to be executed.
            let task: @MainActor @Sendable () async -> Void

            /// Initializes a new `SerialTask`.
            /// - Parameters:
            ///   - owner: The name of the queue that owns this task.
            ///   - id: The UUID for the task. Defaults to a new UUID.
            ///   - file: The file where the task was created.
            ///   - functionName: The function where the task was created.
            ///   - line: The line number where the task was created.
            ///   - task: The asynchronous operation to be performed.
            init(owner: String, id: UUID = .init(), file: String, functionName: String, line: UInt, task: @escaping @MainActor @Sendable () async -> Void) {
                self.owner = owner
                self.id = id
                self.file = file
                self.line = line
                self.functionName = functionName
                self.task = task
                self.created = Date()
            }

            /// Executes the task's operation if it has not been cancelled.
            func execute() async {
                guard !isCancelled else {
                    debug(msg: "Attempted to run", outputTime: true)
                    return
                }
                debug(msg: "Starting", outputTime: true)
                await task()
                debug(msg: "Finished", outputTime: true)
            }

            /// Cancels the current task. Once cancelled, the task will not execute.
            func cancel() {
                debug(msg: "Cancelled SerialTask", outputTime: true)
                _isCancelled.store(true, ordering: .releasing)
            }

            /// A debug description of the `SerialTask`, including owner, file, function, and line.
            var debugDescription: String {
                "\(owner) -- \(file)#\(functionName)::\(line)"
            }

            /// A string representation of the `SerialTask`, including owner, file, function, and line.
            var description: String {
                "\(owner) -- \(file)#\(functionName)::\(line)"
            }

            private var elapsedSeconds: Double {
                let components = createdInstant.duration(to: .now).components
                return Double(components.seconds) + Double(components.attoseconds) / 1e18
            }

            /// Logs a debug message associated with this serial task.
            /// - Parameters:
            ///   - msg: The message to log.
            ///   - outputTime: A boolean indicating whether to include the time elapsed since task creation.
            func debug(msg: String, outputTime: Bool) {
                if outputTime {
                    let timeElapsed = elapsedSeconds * 1000
                    taskLoomLogger.debug("[\(owner)]: SerialTask \(self) \(msg) -- \(timeElapsed)ms")
                } else {
                    taskLoomLogger.debug("[\(owner)]: SerialTask \(self) \(msg)")
                }
            }

        }

        /// A global shared instance of `AsyncOperationSerialQueue` for common use cases.
        public static let global = AsyncOperationSerialQueue(name: "Global")

        /// The name of the queue.
        private let name: String

        /// The continuation synchronously buffers submissions for the single consumer.
        private let continuation: AsyncStream<SerialTask>.Continuation

        /// Protected queue state used across progress cancellation, explicit cancellation, and flushing.
        private let state = Mutex(State())

        private var isCancelled: Bool {
            // Progress invokes its cancellation handler asynchronously. Reject new
            // work as soon as its flag is set, even before that handler runs.
            progress.isCancelled || state.withLock { $0.isCancelled }
        }

        /// A `Progress` object that tracks the progress of operations within the queue.
        public let progress: Progress = {
            let progress = Progress()
            progress.localizedDescription = ""
            progress.localizedAdditionalDescription = ""
            progress.totalUnitCount = 0
            progress.completedUnitCount = 0
            return progress
        }()

        /// The number of tasks that have completed execution.
        @MainActor public var completedTaskCount: Int64 {
            progress.completedUnitCount
        }

        /// The number of tasks remaining in the queue.
        @MainActor public var remainingTaskCount: Int64 {
            progress.totalUnitCount - progress.completedUnitCount
        }

        /// The fraction of tasks completed, ranging from 0.0 to 1.0.
        @MainActor public var fractionCompleted: Double {
            progress.fractionCompleted
        }

        /// The total number of tasks enqueued in this queue.
        @MainActor public var totalTaskCount: Int64 {
            progress.totalUnitCount
        }

        /// Initializes a new `AsyncOperationSerialQueue`.
        /// - Parameters:
        ///   - name: A descriptive name for the queue.
        ///   - priority: The `TaskPriority` for the internal task that processes operations. Defaults to `.medium`.
        ///   - applyTestRestriction: A boolean flag, currently unused, potentially for test-specific behavior.
        public init(name: String, priority: TaskPriority = .medium, applyTestRestriction: Bool = true) {
            self.name = name

            let (stream, continuation) = AsyncStream<SerialTask>.makeStream()
            self.continuation = continuation
            let task = Task(priority: priority) { [weak self] in
                for await operation in stream {
                    guard !Task.isCancelled else {
                        break
                    }
                    await operation.execute()
                    guard let self else {
                        return
                    }
                    if self.progress.completedUnitCount < .max {
                        self.progress.completedUnitCount += 1
                    }
                }
            }
            state.withLock { $0.task = task }

            progress.cancellationHandler = { [weak self] in
                self?.cancel()
            }
        }

        /// Deinitializes the queue, ensuring any pending tasks are cancelled.
        deinit {
            state.withLock { $0.task }?.cancel()
            continuation.finish()
        }

        /// Enqueues a non-cancellable Main Actor operation to be executed serially.
        /// - Parameters:
        ///   - file: The file where this method is called. Defaults to `#file`.
        ///   - functionName: The function where this method is called. Defaults to `#function`.
        ///   - line: The line number where this method is called. Defaults to `#line`.
        ///   - uiOperation: The asynchronous Main Actor operation to enqueue.
        func enqueue(
            _ file: String = #file,
            _ functionName: String = #function,
            _ line: UInt = #line,
            _ uiOperation: @escaping @MainActor @Sendable () async -> Void
        ) async {
            submit(file, functionName, line, uiOperation)
        }

        /// Enqueues a non-cancellable Main Actor operation to be executed serially.
        /// The operation is buffered synchronously and this method returns immediately.
        /// - Parameters:
        ///   - file: The file where this method is called. Defaults to `#file`.
        ///   - functionName: The function where this method is called. Defaults to `#function`.
        ///   - line: The line number where this method is called. Defaults to `#line`.
        ///   - uiOperation: The asynchronous Main Actor operation to enqueue.
        public func enqueue(
            _ file: String = #file,
            _ functionName: String = #function,
            _ line: UInt = #line,
            _ uiOperation: @escaping @MainActor @Sendable () async -> Void
        ) {
            submit(file, functionName, line, uiOperation)
        }

        /// Enqueues a cancellable Main Actor operation to be executed serially.
        /// - Parameters:
        ///   - file: The file where this method is called. Defaults to `#file`.
        ///   - functionName: The function where this method is called. Defaults to `#function`.
        ///   - line: The line number where this method is called. Defaults to `#line`.
        ///   - uiOperation: The asynchronous Main Actor operation to enqueue.
        /// - Returns: An `AnyCancellable` token that can be used to cancel the enqueued operation.
        func enqueueCancellable(
            _ file: String = #file,
            _ functionName: String = #function,
            _ line: UInt = #line,
            _ uiOperation: @escaping @MainActor @Sendable () async -> Void
        ) async -> AnyCancellable {
            let task = submit(file, functionName, line, uiOperation)
            return AnyCancellable { [weak task] in task?.cancel() }
        }

        /// Enqueues a cancellable Main Actor operation to be executed serially.
        /// The operation is buffered synchronously and an `AnyCancellable` token is returned immediately.
        /// - Parameters:
        ///   - file: The file where this method is called. Defaults to `#file`.
        ///   - functionName: The function where this method is called. Defaults to `#function`.
        ///   - line: The line number where this method is called. Defaults to `#line`.
        ///   - uiOperation: The asynchronous Main Actor operation to enqueue.
        /// - Returns: An `AnyCancellable` token that can be used to cancel the enqueued operation.
        public func enqueueCancellable(
            _ file: String = #file,
            _ functionName: String = #function,
            _ line: UInt = #line,
            _ uiOperation: @escaping @MainActor @Sendable () async -> Void
        ) -> AnyCancellable {
            let task = submit(file, functionName, line, uiOperation)
            return AnyCancellable { [weak task] in task?.cancel() }
        }

        @discardableResult
        private func submit(
            _ file: String,
            _ functionName: String,
            _ line: UInt,
            _ operation: @escaping @MainActor @Sendable () async -> Void
        ) -> SerialTask? {
            guard !progress.isCancelled else {
                return nil
            }
            let task = SerialTask(owner: name, file: file, functionName: functionName, line: line, task: operation)
            return state.withLock { state in
                guard !state.isCancelled else {
                    return nil
                }
                task.debug(msg: "Queued", outputTime: false)
                if progress.totalUnitCount < .max {
                    progress.totalUnitCount += 1
                }
                continuation.yield(task)
                return task
            }
        }

        /// Waits for all currently enqueued operations to complete.
        /// This method enqueues a sentinel operation and awaits its execution,
        /// ensuring all previously enqueued operations have finished.
        public func flush() async {
            guard !isCancelled else {
                return
            }
            let id = UUID()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let shouldResume = state.withLock { state in
                    guard !state.isCancelled else {
                        return true
                    }

                    state.flushWaiters.append(FlushWaiter(id: id, continuation: continuation))
                    return false
                }

                guard !shouldResume else {
                    continuation.resume()
                    return
                }

                submit(#file, #function, #line) { [weak self] in
                    self?.resumeFlush(id: id)
                }
                // Progress cancellation can reject the sentinel before its handler runs.
                if isCancelled {
                    resumeFlush(id: id)
                }
            }
        }

        private func resumeFlush(id: UUID) {
            let continuation = state.withLock { state -> CheckedContinuation<Void, Never>? in
                guard let index = state.flushWaiters.firstIndex(where: { $0.id == id }) else {
                    return nil
                }

                return state.flushWaiters.remove(at: index).continuation
            }

            continuation?.resume()
        }

        /// Resets the completed and total task counts in the progress object.
        /// This can be used to clear the progress tracking without cancelling ongoing operations.
        @MainActor public func refreshCount() {
            let countToSubstract = progress.completedUnitCount
            progress.completedUnitCount -= countToSubstract
            progress.totalUnitCount -= countToSubstract
        }

        /// Cancels the internal task, stopping the processing of any further operations in the queue.
        /// Enqueued operations that have not yet started will not be executed.
        public func cancel() {
            let (flushWaiters, task) = state.withLock { state in
                state.isCancelled = true
                let waiters = state.flushWaiters
                state.flushWaiters.removeAll()
                let task = state.task
                state.task = nil
                return (waiters, task)
            }
            flushWaiters.forEach { $0.continuation.resume() }

            task?.cancel()
            continuation.finish()
        }

        /// Stores the queue's cancellation handler in a `Set<AnyCancellable>`, allowing external cancellation management.
        /// - Parameter cancellables: A `Set<AnyCancellable>` to which the cancellation token will be added.
        public func store(in cancellables: inout Set<AnyCancellable>) {
            cancellables.insert(AnyCancellable { [weak self] in
                self?.cancel()
            })
        }
    }
#endif
