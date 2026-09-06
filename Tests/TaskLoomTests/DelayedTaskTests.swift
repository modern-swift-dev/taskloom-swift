import Foundation
@testable import TaskLoom
import Testing

/// Actor for tracking execution state in a thread-safe manner
private actor DelayedTaskTracker {
    var executionTimes: [Date] = []
    var wasExecuted = false
    var executionOrder: [String] = []

    func recordExecution() {
        executionTimes.append(Date())
        wasExecuted = true
    }

    func appendOrder(_ value: String) {
        executionOrder.append(value)
    }

    func getWasExecuted() -> Bool {
        wasExecuted
    }

    func getExecutionTimes() -> [Date] {
        executionTimes
    }

    func getExecutionOrder() -> [String] {
        executionOrder
    }
}

@Suite(.serialized) struct DelayedTaskTests {

    // MARK: - Basic Execution

    @Test func delayedTaskExecutesHandler() async {
        let tracker = DelayedTaskTracker()

        let task = DelayedTask {
            await tracker.recordExecution()
        }

        await task.value

        let wasExecuted = await tracker.getWasExecuted()
        #expect(wasExecuted)
    }

    @Test func delayedTaskExecutesWithZeroDelay() async {
        let tracker = DelayedTaskTracker()

        let task = DelayedTask(delay: 0) {
            await tracker.recordExecution()
        }

        await task.value

        let wasExecuted = await tracker.getWasExecuted()
        #expect(wasExecuted)
    }

    @Test func delayedTaskExecutesAfterDelay() async {
        let tracker = DelayedTaskTracker()
        let startTime = Date()

        let task = DelayedTask(delay: 0.05) {
            await tracker.recordExecution()
        }

        await task.value

        let times = await tracker.getExecutionTimes()
        #expect(times.count == 1)

        // Verify some delay occurred (at least 40ms to account for timing variance)
        let elapsed = times[0].timeIntervalSince(startTime)
        #expect(elapsed >= 0.04)
    }

    @Test
    @MainActor func delayedTaskExecutesOnMainActor() async {
        var didExecuteOnMain = false

        let task = DelayedTask {
            MainActor.assertIsolated()
            didExecuteOnMain = true
        }

        await task.value
        #expect(didExecuteOnMain)
    }

    // MARK: - Cancellation

    @Test func delayedTaskCanBeCancelledBeforeDelay() async {
        let tracker = DelayedTaskTracker()

        let task = DelayedTask(delay: 1.0) {
            await tracker.recordExecution()
        }

        // Cancel immediately
        task.cancel()

        // Wait a bit to ensure the task had time to check cancellation
        try? await Task.sleep(for: .milliseconds(50))

        let wasExecuted = await tracker.getWasExecuted()
        #expect(task.isCancelled)
        #expect(!wasExecuted)
    }

    @Test func delayedTaskCanBeCancelledDuringDelay() async {
        let tracker = DelayedTaskTracker()

        let task = DelayedTask(delay: 0.5) {
            await tracker.recordExecution()
        }

        // Cancel after a short time but before delay completes
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()

        // Wait for task to complete
        await task.value

        let wasExecuted = await tracker.getWasExecuted()
        #expect(task.isCancelled)
        #expect(!wasExecuted)
    }

    @Test func delayedTaskReturnsNonThrowingTask() async {
        let task = DelayedTask {
            // Handler doesn't throw
        }

        // Verify return type is Task<Void, Never>
        #expect(type(of: task) == Task<Void, Never>.self)
        await task.value
    }

    // MARK: - Throwing Variant

    @Test func delayedTaskThrowingVariantExecutes() async throws {
        let tracker = DelayedTaskTracker()

        let task = DelayedTask {
            await tracker.recordExecution()
            // This is the throwing variant even though we don't throw
        } as Task<Void, any Error>

        try await task.value

        let wasExecuted = await tracker.getWasExecuted()
        #expect(wasExecuted)
    }

    @Test func delayedTaskThrowingVariantPropagatesError() async {
        struct TestError: Error {}

        let task = DelayedTask {
            throw TestError()
        } as Task<Void, any Error>

        do {
            try await task.value
            Issue.record("Expected error to be thrown")
        } catch is TestError {
            // Expected
        } catch {
            Issue.record("Expected TestError but got \(error)")
        }
    }

    @Test func delayedTaskThrowingCanBeCancelled() async {
        let tracker = DelayedTaskTracker()

        let task = DelayedTask(delay: 0.5) {
            await tracker.recordExecution()
        } as Task<Void, any Error>

        task.cancel()

        // Wait for task to complete
        _ = try? await task.value

        let wasExecuted = await tracker.getWasExecuted()
        #expect(task.isCancelled)
        #expect(!wasExecuted)
    }

    // MARK: - Priority

    @Test func delayedTaskRespectsTaskPriority() async {
        let tracker = DelayedTaskTracker()

        // Create tasks with different priorities
        let highTask = DelayedTask(priority: .high, delay: 0) {
            await tracker.appendOrder("high")
        }

        let lowTask = DelayedTask(priority: .low, delay: 0) {
            await tracker.appendOrder("low")
        }

        await highTask.value
        await lowTask.value

        // Both should execute (order not guaranteed due to scheduler)
        let order = await tracker.getExecutionOrder()
        #expect(order.contains("high"))
        #expect(order.contains("low"))
    }

    // MARK: - TaskManager Integration

    @Test func delayedTaskIntegratesWithTaskManager() async {
        let manager = TaskManager.shared
        let stateBefore = manager.getState()

        let task = DelayedTask(delay: 0.01) {
            // Small work
        }

        await task.value

        // Give time for completion tracking
        try? await Task.sleep(for: .milliseconds(10))

        let stateAfter = manager.getState()

        #expect(stateAfter.nbCreatedTaskTotal > stateBefore.nbCreatedTaskTotal)
        #expect(stateAfter.nbCompletedTaskCount > stateBefore.nbCompletedTaskCount)
    }

    @Test func delayedTaskCancellationTrackedByTaskManager() async {
        let manager = TaskManager.shared
        let stateBefore = manager.getState()

        let task = DelayedTask(delay: 1.0) {
            // Won't execute due to cancellation
        }

        task.cancel()
        await task.value

        try? await Task.sleep(for: .milliseconds(10))

        let stateAfter = manager.getState()

        #expect(stateAfter.nbCancelledTaskCount > stateBefore.nbCancelledTaskCount)
    }
}
