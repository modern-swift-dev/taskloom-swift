import Foundation
@testable import TaskLoom
import Testing

/// Actor for tracking execution state in a thread-safe manner
private actor UITaskTracker {
    var wasExecuted = false
    var results: [Int] = []
    var executionOrder: [String] = []

    func markExecuted() {
        wasExecuted = true
    }

    func appendResult(_ value: Int) {
        results.append(value)
    }

    func appendOrder(_ value: String) {
        executionOrder.append(value)
    }

    func getWasExecuted() -> Bool {
        wasExecuted
    }

    func getResults() -> [Int] {
        results
    }

    func getExecutionOrder() -> [String] {
        executionOrder
    }
}

@Suite(.serialized) struct UITaskTests {

    @Test func uiTaskExecutesHandler() async {
        let tracker = UITaskTracker()

        let task = UITask {
            await tracker.markExecuted()
        }

        await task.value
        let wasExecuted = await tracker.getWasExecuted()
        #expect(wasExecuted)
    }

    @Test
    @MainActor func uiTaskExecutesOnMainActor() async {
        // UITask handlers are annotated with @MainActor, so they execute on the main actor
        // We verify this by checking that MainActor.assertIsolated() doesn't crash
        var didExecute = false

        let task = UITask {
            // This code runs on MainActor - if it wasn't, this would crash
            MainActor.assertIsolated()
            didExecute = true
        }

        await task.value
        #expect(didExecute)
    }

    @Test func uiTaskCanBeCancelled() async {
        let task = UITask {
            try? await Task.sleep(for: .milliseconds(100))
        }

        task.cancel()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(task.isCancelled)
    }

    @Test func uiTaskReturnsTaskHandle() async {
        let task = UITask {
            // Empty handler
        }

        // Verify it returns a proper Task<Void, Never>
        #expect(type(of: task) == Task<Void, Never>.self)
        await task.value
    }

    @Test func uiTaskWithDifferentPriorities() async {
        let tracker = UITaskTracker()

        // Create tasks with different priorities
        let lowTask = UITask(.low) {
            await tracker.appendOrder("low")
        }

        let highTask = UITask(.high) {
            await tracker.appendOrder("high")
        }

        await lowTask.value
        await highTask.value

        // Both should execute
        let order = await tracker.getExecutionOrder()
        #expect(order.contains("low"))
        #expect(order.contains("high"))
    }

    @Test func uiTaskAsyncCallback() async {
        let tracker = UITaskTracker()

        let task = UITask {
            await tracker.appendResult(1)
            try? await Task.sleep(for: .milliseconds(10))
            await tracker.appendResult(2)
            try? await Task.sleep(for: .milliseconds(10))
            await tracker.appendResult(3)
        }

        await task.value

        let results = await tracker.getResults()
        #expect(results == [1, 2, 3])
    }

    @Test
    @MainActor func uiTaskCallbackTypes() async {
        // Test UITaskCallback (sync)
        let syncCallback: UITaskCallback = {
            // This is a sync MainActor callback
        }
        syncCallback()

        // Test UITaskAsyncCallback (async)
        let asyncCallback: UITaskAsyncCallback = {
            try? await Task.sleep(for: .milliseconds(1))
        }
        await asyncCallback()
    }
}
