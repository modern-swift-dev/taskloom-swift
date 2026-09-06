#if canImport(Combine)
import Combine
import Foundation
@testable import TaskLoom
import Testing

/// Actor for tracking execution state in a thread-safe manner
private actor ExecutionTracker {
    var wasExecuted = false
    var executionCount = 0
    var childTasksStarted = 0
    var childTasksCompleted = 0
    var didComplete = false

    func markExecuted() {
        wasExecuted = true
    }

    func incrementCount() {
        executionCount += 1
    }

    func incrementStarted() {
        childTasksStarted += 1
    }

    func incrementCompleted() {
        childTasksCompleted += 1
    }

    func markComplete() {
        didComplete = true
    }

    func getWasExecuted() -> Bool {
        wasExecuted
    }

    func getExecutionCount() -> Int {
        executionCount
    }

    func getChildTasksCompleted() -> Int {
        childTasksCompleted
    }

    func getDidComplete() -> Bool {
        didComplete
    }
}

@Suite(.serialized) struct TaskCancellableTests {

    // MARK: - Task Cancellable Conformance

    @Test func taskConformsToCancellable() async {
        let tracker = ExecutionTracker()
        let task = Task {
            // Check cancellation cooperatively
            guard !Task.isCancelled else {
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else {
                return
            }
            await tracker.markExecuted()
        }

        // Task conforms to Cancellable
        let cancellable: Cancellable = task
        cancellable.cancel()

        // Wait for task to complete (should exit early due to cancellation)
        await task.value

        let wasExecuted = await tracker.getWasExecuted()
        #expect(task.isCancelled)
        #expect(!wasExecuted)
    }

    @Test func taskEraseToAnyCancellable() async {
        let tracker = ExecutionTracker()
        let task = Task {
            guard !Task.isCancelled else {
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else {
                return
            }
            await tracker.markExecuted()
        }

        let anyCancellable = task.eraseToAnyCancellable()

        // Cancel via AnyCancellable
        anyCancellable.cancel()

        await task.value

        let wasExecuted = await tracker.getWasExecuted()
        #expect(task.isCancelled)
        #expect(!wasExecuted)
    }

    @Test func anyCancellableCanBeStoredInSet() {
        var cancellables = Set<AnyCancellable>()

        let task1 = Task {
            try? await Task.sleep(for: .milliseconds(50))
        }

        let task2 = Task {
            try? await Task.sleep(for: .milliseconds(50))
        }

        task1.eraseToAnyCancellable().store(in: &cancellables)
        task2.eraseToAnyCancellable().store(in: &cancellables)

        #expect(cancellables.count == 2)

        // Cancel all by clearing the set - this marks tasks as cancelled
        cancellables.removeAll()

        #expect(task1.isCancelled)
        #expect(task2.isCancelled)
    }

    @Test func taskWithResultEraseToAnyCancellable() {
        let task = Task { () -> Int in
            try? await Task.sleep(for: .milliseconds(100))
            return 42
        }

        let anyCancellable = task.eraseToAnyCancellable()
        anyCancellable.cancel()

        #expect(task.isCancelled)
    }

    @Test func throwingTaskEraseToAnyCancellable() async throws {
        let task = Task { () throws -> Int in
            // This will throw CancellationError when cancelled
            try await Task.sleep(for: .milliseconds(500))
            return 42
        }

        let anyCancellable = task.eraseToAnyCancellable()
        anyCancellable.cancel()

        #expect(task.isCancelled)

        // Verify the task throws CancellationError
        do {
            _ = try await task.value
            Issue.record("Expected CancellationError to be thrown")
        } catch is CancellationError {
            // Expected
        } catch {
            Issue.record("Expected CancellationError but got \(error)")
        }
    }

    // MARK: - TaskGroup Cancellable

    @Test func taskGroupConformsToCancellable() async {
        // Verify TaskGroup has cancel() method that calls cancelAll()
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                try? await Task.sleep(for: .milliseconds(100))
            }

            // Cancel using Cancellable conformance
            let cancellable: Cancellable = group
            cancellable.cancel()

            // Verify the group was cancelled
            #expect(group.isCancelled)
        }
    }

    @Test func taskGroupEraseToAnyCancellable() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                try? await Task.sleep(for: .milliseconds(100))
            }

            let anyCancellable = group.eraseToAnyCancellable()
            anyCancellable.cancel()

            #expect(group.isCancelled)
        }
    }

    // MARK: - ThrowingTaskGroup Cancellable

    @Test func throwingTaskGroupConformsToCancellable() async {
        await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await Task.sleep(for: .milliseconds(100))
            }

            let cancellable: Cancellable = group
            cancellable.cancel()

            #expect(group.isCancelled)
        }
    }

    @Test func throwingTaskGroupEraseToAnyCancellable() async {
        await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await Task.sleep(for: .milliseconds(100))
            }

            let anyCancellable = group.eraseToAnyCancellable()
            anyCancellable.cancel()

            #expect(group.isCancelled)
        }
    }

    // MARK: - Integration with Combine patterns

    @Test func taskCancellationIntegrationWithCombine() async {
        var cancellables = Set<AnyCancellable>()
        let tracker = ExecutionTracker()

        // Create a task that checks cancellation cooperatively
        let task = Task {
            for _ in 0 ..< 100 {
                guard !Task.isCancelled else {
                    return
                }
                try? await Task.sleep(for: .milliseconds(10))
            }
            await tracker.markComplete()
        }

        // Store it like a Combine subscription
        task.eraseToAnyCancellable().store(in: &cancellables)

        // Simulate view disappearing - clear cancellables
        cancellables.removeAll()

        // Wait for the task to finish (should exit early)
        await task.value

        let didComplete = await tracker.getDidComplete()
        #expect(task.isCancelled)
        #expect(!didComplete)
    }
}

#endif
