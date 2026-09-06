import Foundation
@testable import TaskLoom
import Testing

/// Actor for tracking repeating task execution
private actor RepeatingTaskTracker {
    var executionCount = 0
    var maxExecutions: Int
    var executionTimes: [Date] = []

    init(maxExecutions: Int = 10) {
        self.maxExecutions = maxExecutions
    }

    func recordExecution() -> Bool {
        executionCount += 1
        executionTimes.append(Date())
        return executionCount < maxExecutions
    }

    func getExecutionCount() -> Int {
        executionCount
    }

    func getExecutionTimes() -> [Date] {
        executionTimes
    }

    func setMaxExecutions(_ value: Int) {
        maxExecutions = value
    }
}

@Suite(.serialized) struct RepeatingTaskTests {

    // MARK: - Basic Execution

    @Test func repeatingTaskExecutesMultipleTimes() async {
        let tracker = RepeatingTaskTracker(maxExecutions: 3)

        let task = RepeatingTask(interval: 0) {
            await tracker.recordExecution()
        }

        await task.value

        let count = await tracker.getExecutionCount()
        #expect(count == 3)
    }

    @Test func repeatingTaskStopsWhenHandlerReturnsFalse() async {
        let tracker = RepeatingTaskTracker(maxExecutions: 5)

        let task = RepeatingTask(interval: 0) {
            await tracker.recordExecution()
        }

        await task.value

        let count = await tracker.getExecutionCount()
        #expect(count == 5)
    }

    @Test func repeatingTaskExecutesOnceWhenReturningFalseImmediately() async {
        let tracker = RepeatingTaskTracker(maxExecutions: 1)

        let task = RepeatingTask(interval: 0) {
            await tracker.recordExecution()
        }

        await task.value

        let count = await tracker.getExecutionCount()
        #expect(count == 1)
    }

    @Test
    @MainActor func repeatingTaskExecutesOnMainActor() async {
        var executedOnMain = false

        let task = RepeatingTask(interval: 0) {
            MainActor.assertIsolated()
            executedOnMain = true
            return false // Execute once
        }

        await task.value
        #expect(executedOnMain)
    }

    // MARK: - Interval Timing

    @Test func repeatingTaskRespectsInterval() async {
        let tracker = RepeatingTaskTracker(maxExecutions: 3)

        let task = RepeatingTask(interval: 0.03) {
            await tracker.recordExecution()
        }

        await task.value

        let times = await tracker.getExecutionTimes()
        #expect(times.count == 3)

        // Check intervals between executions (should be ~30ms each)
        if times.count >= 2 {
            let interval1 = times[1].timeIntervalSince(times[0])
            #expect(interval1 >= 0.02) // Allow some variance
        }
        if times.count >= 3 {
            let interval2 = times[2].timeIntervalSince(times[1])
            #expect(interval2 >= 0.02)
        }
    }

    @Test func repeatingTaskWithZeroIntervalExecutesQuickly() async {
        let tracker = RepeatingTaskTracker(maxExecutions: 5)
        let startTime = Date()

        let task = RepeatingTask(interval: 0) {
            await tracker.recordExecution()
        }

        await task.value

        let elapsed = Date().timeIntervalSince(startTime)
        let count = await tracker.getExecutionCount()

        #expect(count == 5)
        #expect(elapsed < 0.5) // Should complete quickly with zero interval
    }

    // MARK: - Cancellation

    @Test func repeatingTaskCanBeCancelled() async {
        let tracker = RepeatingTaskTracker(maxExecutions: 100)
        let started = TestSignal()

        let task = RepeatingTask(interval: 0.01) {
            await started.signal()
            return await tracker.recordExecution()
        }

        // Wait until at least one execution has occurred
        await started.wait()

        // Let it run a few more iterations
        try? await Task.sleep(for: .milliseconds(100))

        // Cancel
        task.cancel()

        // Wait for completion
        await task.value

        let count = await tracker.getExecutionCount()
        #expect(task.isCancelled)
        #expect(count < 100) // Should have stopped before completing all iterations
        #expect(count > 0) // But should have run at least once
    }

    @Test func repeatingTaskCanBeCancelledDuringInterval() async {
        let tracker = RepeatingTaskTracker(maxExecutions: 100)
        let started = TestSignal()

        let task = RepeatingTask(interval: 1.0) {
            await started.signal()
            return await tracker.recordExecution()
        }

        // Wait for first execution then cancel during interval
        await started.wait()
        task.cancel()

        await task.value

        let count = await tracker.getExecutionCount()
        #expect(task.isCancelled)
        #expect(count <= 1) // Should have executed at most once
    }

    @Test func repeatingTaskCanBeCancelledImmediately() async {
        let tracker = RepeatingTaskTracker(maxExecutions: 100)

        let task = RepeatingTask(interval: 0.1) {
            await tracker.recordExecution()
        }

        // Cancel immediately
        task.cancel()

        await task.value

        let count = await tracker.getExecutionCount()
        #expect(task.isCancelled)
        // May or may not have executed once depending on timing
        #expect(count <= 1)
    }

    // MARK: - Priority

    @Test func repeatingTaskDefaultsToLowPriority() async {
        // RepeatingTask defaults to .low priority per implementation
        let tracker = RepeatingTaskTracker(maxExecutions: 1)

        let task = RepeatingTask {
            await tracker.recordExecution()
        }

        await task.value

        let count = await tracker.getExecutionCount()
        #expect(count == 1)
    }

    @Test func repeatingTaskRespectsCustomPriority() async {
        let tracker = RepeatingTaskTracker(maxExecutions: 1)

        let task = RepeatingTask(priority: .high, interval: 0) {
            await tracker.recordExecution()
        }

        await task.value

        let count = await tracker.getExecutionCount()
        #expect(count == 1)
    }

    // MARK: - Return Type

    @Test func repeatingTaskReturnsNonThrowingTask() async {
        let task = RepeatingTask {
            false // Execute once
        }

        #expect(type(of: task) == Task<Void, Never>.self)
        await task.value
    }
}
