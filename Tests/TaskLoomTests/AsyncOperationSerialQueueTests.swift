#if canImport(Combine)
import Combine
import Foundation
@testable import TaskLoom
import Testing

/// Actor for tracking serial queue execution order
private actor SerialQueueTracker {
    var executionOrder: [Int] = []
    var concurrentExecutions = 0
    var maxConcurrentExecutions = 0

    func startExecution(_ id: Int) {
        concurrentExecutions += 1
        if concurrentExecutions > maxConcurrentExecutions {
            maxConcurrentExecutions = concurrentExecutions
        }
    }

    func endExecution(_ id: Int) {
        executionOrder.append(id)
        concurrentExecutions -= 1
    }

    func getExecutionOrder() -> [Int] {
        executionOrder
    }

    func getMaxConcurrent() -> Int {
        maxConcurrentExecutions
    }

    func getConcurrent() -> Int {
        concurrentExecutions
    }
}

private typealias SerialQueueOperation = @MainActor @Sendable () async -> Void

@Suite(.serialized) struct AsyncOperationSerialQueueTests {

    @Test func idleQueueIsReleasedAfterConsumerStarts() async throws {
        var queue: AsyncOperationSerialQueue? = AsyncOperationSerialQueue(name: "Idle lifetime")
        weak var weakQueue = queue
        defer {
            weakQueue?.cancel()
            weakQueue = nil
        }

        await queue?.flush()
        queue = nil

        // Allow the consumer's current iteration to finish before checking its idle lifetime.
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while weakQueue != nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(weakQueue == nil)
    }

    @Test func concurrentCancellationIsIdempotent() async {
        let queue = AsyncOperationSerialQueue(name: "Concurrent cancellation")
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<32 {
                group.addTask { queue.cancel() }
            }
        }
        await queue.flush()
        let tracker = SerialQueueTracker()
        await queue.enqueue { await tracker.startExecution(1) }
        #expect(await tracker.getConcurrent() == 0)
    }

    // MARK: - Basic Execution

    @Test func queueExecutesOperation() async {
        let queue = AsyncOperationSerialQueue(name: "Test")
        let tracker = SerialQueueTracker()

        await queue.enqueue {
            await tracker.startExecution(1)
            await tracker.endExecution(1)
        }

        // Wait for execution using flush
        try? await Task.sleep(for: .milliseconds(10))

        let order = await tracker.getExecutionOrder()
        #expect(order == [1])
    }

    @Test func queueExecutesMultipleOperations() async {
        let queue = AsyncOperationSerialQueue(name: "Test")
        let tracker = SerialQueueTracker()

        for i in 1 ... 3 {
            await queue.enqueue {
                await tracker.startExecution(i)
                try? await Task.sleep(for: .milliseconds(10))
                await tracker.endExecution(i)
            }
        }

        // Wait for all executions using flush
        await queue.flush()

        let order = await tracker.getExecutionOrder()
        #expect(order.count == 3)
    }

    // MARK: - Serial Execution (FIFO)

    @Test func queueExecutesOperationsSerially() async {
        let queue = AsyncOperationSerialQueue(name: "Serial")
        let tracker = SerialQueueTracker()

        // Enqueue multiple operations with delays
        for i in 1 ... 5 {
            await queue.enqueue {
                await tracker.startExecution(i)
                try? await Task.sleep(for: .milliseconds(20))
                await tracker.endExecution(i)
            }
        }

        // Wait for all to complete using flush
        await queue.flush()

        let maxConcurrent = await tracker.getMaxConcurrent()
        let order = await tracker.getExecutionOrder()

        // Serial queue should never have more than 1 concurrent execution
        #expect(maxConcurrent == 1)
        // Operations should complete in FIFO order
        #expect(order == [1, 2, 3, 4, 5])
    }

    @Test @MainActor func publicSubmissionsPreserveOrderBeforeImmediateFlush() async {
        let queue = AsyncOperationSerialQueue(name: "Public FIFO")
        defer { queue.cancel() }
        let enqueue: (String, String, UInt, @escaping SerialQueueOperation) -> Void = queue.enqueue
        let enqueueCancellable: (String, String, UInt, @escaping SerialQueueOperation) -> AnyCancellable = queue.enqueueCancellable
        var tokens: [AnyCancellable] = []
        var order: [Int] = []
        var activeCount = 0
        var maxActiveCount = 0

        for id in 0..<100 {
            let operation: SerialQueueOperation = {
                activeCount += 1
                maxActiveCount = max(maxActiveCount, activeCount)
                await Task.yield()
                order.append(id)
                activeCount -= 1
            }
            if id.isMultiple(of: 2) {
                enqueue(#file, #function, #line, operation)
            } else {
                tokens.append(enqueueCancellable(#file, #function, #line, operation))
            }
        }

        // Acceptance must finish before returning to the caller, without an actor hop.
        #expect(queue.totalTaskCount == 100)
        await queue.flush()
        #expect(order == Array(0..<100))
        #expect(maxActiveCount == 1)
        withExtendedLifetime(tokens) {}
    }

    @Test func queueMaintainsFIFOOrder() async {
        let queue = AsyncOperationSerialQueue(name: "FIFO")
        let tracker = SerialQueueTracker()

        // Enqueue in specific order
        await queue.enqueue {
            await tracker.endExecution(1)
        }
        await queue.enqueue {
            await tracker.endExecution(2)
        }
        await queue.enqueue {
            await tracker.endExecution(3)
        }

        // Wait using flush
        await queue.flush()

        let order = await tracker.getExecutionOrder()
        #expect(order == [1, 2, 3])
    }

    // MARK: - Progress Tracking

    @Test @MainActor func queueTracksProgress() async {
        let queue = AsyncOperationSerialQueue(name: "Progress")

        #expect(queue.totalTaskCount == 0)
        #expect(queue.completedTaskCount == 0)

        await queue.enqueue {
            try? await Task.sleep(for: .milliseconds(30))
        }
        await queue.enqueue {
            try? await Task.sleep(for: .milliseconds(30))
        }

        // Give time for tasks to be enqueued
        try? await Task.sleep(for: .milliseconds(20))

        #expect(queue.totalTaskCount == 2)

        // Wait for completion (use sleep since flush adds a sentinel task to progress)
        try? await Task.sleep(for: .milliseconds(150))

        #expect(queue.completedTaskCount == 2)
    }

    @Test @MainActor func queueFractionCompleted() async {
        let queue = AsyncOperationSerialQueue(name: "Fraction")

        await queue.enqueue {
            try? await Task.sleep(for: .milliseconds(50))
        }
        await queue.enqueue {
            try? await Task.sleep(for: .milliseconds(50))
        }

        // Initially
        try? await Task.sleep(for: .milliseconds(10))
        #expect(queue.fractionCompleted >= 0.0)

        // After completion (use sleep since flush adds a sentinel task to progress)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(queue.fractionCompleted == 1.0)
    }

    @Test @MainActor func queueRemainingTaskCount() async {
        let queue = AsyncOperationSerialQueue(name: "Remaining")

        await queue.enqueue {
            try? await Task.sleep(for: .milliseconds(100))
        }
        await queue.enqueue {
            try? await Task.sleep(for: .milliseconds(100))
        }
        await queue.enqueue {
            try? await Task.sleep(for: .milliseconds(100))
        }

        try? await Task.sleep(for: .milliseconds(20))

        // Some tasks should be remaining
        let remaining = queue.remainingTaskCount
        #expect(remaining >= 1)

        // Wait for all to complete using flush
        await queue.flush()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(queue.remainingTaskCount == 0)
    }

    // MARK: - Cancellation

    @Test func queueCanBeCancelled() async {
        let queue = AsyncOperationSerialQueue(name: "Cancel")
        let tracker = SerialQueueTracker()

        // Enqueue first operation that takes time
        await queue.enqueue {
            await tracker.startExecution(1)
            try? await Task.sleep(for: .milliseconds(200))
            await tracker.endExecution(1)
        }

        // Cancel the queue - this should prevent future operations from running
        queue.cancel()

        // Try to enqueue more operations after cancellation
        await queue.enqueue {
            await tracker.endExecution(2)
        }

        // Wait for everything to settle
        try? await Task.sleep(for: .milliseconds(300))

        let order = await tracker.getExecutionOrder()
        // After cancel, the cancelled queue task stops processing
        // Operations already in flight may complete, but new ones won't start
        #expect(order.count <= 1)
    }

    @Test func enqueueCancellableReturnsToken() async {
        let queue = AsyncOperationSerialQueue(name: "Token")
        let tracker = SerialQueueTracker()

        // The cancellable token can be stored and used later
        var cancellables = Set<AnyCancellable>()

        let cancellable1 = await queue.enqueueCancellable {
            await tracker.endExecution(1)
        }
        cancellable1.store(in: &cancellables)

        #expect(cancellables.count == 1)

        // Wait for execution using flush
        await queue.flush()

        let order = await tracker.getExecutionOrder()
        #expect(order.contains(1))
    }

    @Test func publicEnqueueSchedulesOperation() async {
        let queue = AsyncOperationSerialQueue(name: "PublicEnqueue")
        let tracker = SerialQueueTracker()
        let enqueue: (String, String, UInt, @escaping SerialQueueOperation) -> Void = queue.enqueue

        enqueue("AsyncOperationSerialQueueTests.swift", "publicEnqueueSchedulesOperation", 0) {
            await tracker.endExecution(1)
        }

        try? await Task.sleep(for: .milliseconds(10))
        await queue.flush()

        let order = await tracker.getExecutionOrder()
        #expect(order == [1])
    }

    @Test func publicEnqueueCancellableSchedulesOperation() async {
        let queue = AsyncOperationSerialQueue(name: "PublicToken")
        let tracker = SerialQueueTracker()
        let enqueue: (String, String, UInt, @escaping SerialQueueOperation) -> AnyCancellable = queue.enqueueCancellable

        let cancellable = enqueue("AsyncOperationSerialQueueTests.swift", "publicEnqueueCancellableSchedulesOperation", 0) {
            await tracker.endExecution(1)
        }

        try? await Task.sleep(for: .milliseconds(10))
        await queue.flush()

        let order = await tracker.getExecutionOrder()
        #expect(order == [1])
        _ = cancellable
    }

    @Test func publicEnqueueCancellableCanCancelBeforeExecution() async {
        let queue = AsyncOperationSerialQueue(name: "PublicCancel")
        let tracker = SerialQueueTracker()
        let enqueue: (String, String, UInt, @escaping SerialQueueOperation) -> AnyCancellable = queue.enqueueCancellable

        await queue.enqueue {
            try? await Task.sleep(for: .milliseconds(100))
            await tracker.endExecution(0)
        }

        let cancellable = enqueue("AsyncOperationSerialQueueTests.swift", "publicEnqueueCancellableCanCancelBeforeExecution", 0) {
            await tracker.endExecution(1)
        }
        cancellable.cancel()

        await queue.flush()

        let order = await tracker.getExecutionOrder()
        #expect(order == [0])
    }

    @Test func enqueueCancellableCanBeCancelledByDeallocatingToken() async {
        let queue = AsyncOperationSerialQueue(name: "Dealloc")
        let tracker = SerialQueueTracker()

        // First operation blocks the queue
        await queue.enqueue {
            try? await Task.sleep(for: .milliseconds(100))
            await tracker.endExecution(0)
        }

        // Create cancellable in a scope so it deallocates
        do {
            let cancellable = await queue.enqueueCancellable {
                await tracker.endExecution(1)
            }
            // Token goes out of scope and deallocates, which should cancel
            _ = cancellable
        }

        // Third operation
        await queue.enqueue {
            await tracker.endExecution(2)
        }

        // Wait for completion using flush
        await queue.flush()

        let order = await tracker.getExecutionOrder()
        // First and third should execute, second may or may not depending on timing
        #expect(order.contains(0))
        #expect(order.contains(2))
    }

    @Test func queueConformsToCancellable() async {
        let queue = AsyncOperationSerialQueue(name: "Conformance")

        // Queue conforms to Cancellable
        let cancellable: Cancellable = queue
        cancellable.cancel()

        // After cancellation, new operations should not be processed
        await queue.enqueue {
            // This should not execute
        }
    }

    @Test func queueCanBeStoredInCancellables() {
        var cancellables = Set<AnyCancellable>()
        let queue = AsyncOperationSerialQueue(name: "Store")

        queue.store(in: &cancellables)

        #expect(cancellables.count == 1)

        // Clearing cancellables should cancel the queue
        cancellables.removeAll()
    }

    @Test func progressCancellationHandlerCancelsQueue() async {
        let queue = AsyncOperationSerialQueue(name: "ProgressCancel")
        let tracker = SerialQueueTracker()

        queue.progress.cancel()

        await queue.enqueue {
            await tracker.endExecution(1)
        }
        await queue.flush()

        let order = await tracker.getExecutionOrder()
        #expect(order.isEmpty)
    }

    // MARK: - Refresh Count

    @Test @MainActor func refreshCountResetsProgress() async {
        let queue = AsyncOperationSerialQueue(name: "Refresh")

        await queue.enqueue {
            try? await Task.sleep(for: .milliseconds(10))
        }
        await queue.enqueue {
            try? await Task.sleep(for: .milliseconds(10))
        }

        // Wait for completion (use sleep since flush adds a sentinel task to progress)
        try? await Task.sleep(for: .milliseconds(100))

        #expect(queue.completedTaskCount == 2)
        #expect(queue.totalTaskCount == 2)

        // Refresh count (now @MainActor)
        queue.refreshCount()

        #expect(queue.completedTaskCount == 0)
        #expect(queue.totalTaskCount == 0)
    }

    // MARK: - Global Queue

    @Test func globalQueueExists() {
        let global = AsyncOperationSerialQueue.global

        #expect(global !== AsyncOperationSerialQueue(name: "Other"))
    }

    @Test func globalQueueExecutesOperations() async {
        let tracker = SerialQueueTracker()

        await AsyncOperationSerialQueue.global.enqueue {
            await tracker.endExecution(1)
        }

        // Wait using flush
        await AsyncOperationSerialQueue.global.flush()

        let order = await tracker.getExecutionOrder()
        #expect(order.contains(1))
    }

    // MARK: - MainActor Execution

    @Test
    @MainActor func queueExecutesOnMainActor() async {
        let queue = AsyncOperationSerialQueue(name: "MainActor")
        var executedOnMain = false

        await queue.enqueue {
            MainActor.assertIsolated()
            executedOnMain = true
        }

        try? await Task.sleep(for: .milliseconds(50))

        #expect(executedOnMain)
    }

    // MARK: - Edge Cases

    @Test @MainActor func queueHandlesEmptyOperations() async {
        let queue = AsyncOperationSerialQueue(name: "Empty")

        await queue.enqueue {
            // Empty operation
        }
        await queue.enqueue {
            // Another empty operation
        }

        // Wait for completion (use sleep since flush adds a sentinel task to progress)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(queue.completedTaskCount == 2)
    }

    @Test func queueHandlesRapidEnqueue() async {
        let queue = AsyncOperationSerialQueue(name: "Rapid")
        let tracker = SerialQueueTracker()

        // Rapidly enqueue many operations
        for i in 1 ... 20 {
            await queue.enqueue {
                await tracker.endExecution(i)
            }
        }

        // Wait for all to complete using flush
        await queue.flush()

        let order = await tracker.getExecutionOrder()
        #expect(order.count == 20)
        // Verify FIFO order maintained
        #expect(order == Array(1 ... 20))
    }

    // MARK: - Flush

    @Test func flushWaitsForAllOperations() async {
        let queue = AsyncOperationSerialQueue(name: "Flush")
        let tracker = SerialQueueTracker()

        // Enqueue operations with delays
        for i in 1 ... 3 {
            await queue.enqueue {
                await tracker.startExecution(i)
                try? await Task.sleep(for: .milliseconds(20))
                await tracker.endExecution(i)
            }
        }

        // flush() should wait until all operations complete
        await queue.flush()

        let order = await tracker.getExecutionOrder()
        #expect(order == [1, 2, 3])
    }

    @Test func flushOnCancelledQueueReturnsImmediately() async {
        let queue = AsyncOperationSerialQueue(name: "FlushCancelled")

        queue.cancel()

        // flush() on cancelled queue should return without hanging
        await queue.flush()
    }

    @Test func flushOnEmptyQueueReturnsImmediately() async {
        let queue = AsyncOperationSerialQueue(name: "FlushEmpty")

        // flush() on empty queue should complete
        await queue.flush()
    }
}

#endif
