import Foundation
@testable import TaskLoom
import Testing

/// Actor for tracking concurrent execution
private actor ConcurrencyTracker {
    var current = 0
    var maxConcurrent = 0
    var completedCount = 0
    var events: [String] = []

    func start(_ id: Int) {
        current += 1
        maxConcurrent = max(maxConcurrent, current)
        events.append("start-\(id)")
    }

    func end(_ id: Int) {
        current -= 1
        completedCount += 1
        events.append("end-\(id)")
    }

    func getMaxConcurrent() -> Int {
        maxConcurrent
    }

    func getCompletedCount() -> Int {
        completedCount
    }

    func getEvents() -> [String] {
        events
    }
}

@Suite(.serialized) struct AsyncSemaphoreTests {

    // MARK: - Basic Properties

    @Test func initializesWithCorrectLimit() async {
        let semaphore = AsyncSemaphore(limit: 5)

        let limit = await semaphore.limit
        let available = await semaphore.availablePermits

        #expect(limit == 5)
        #expect(available == 5)
    }

    @Test func hasAvailablePermitsWhenNotFull() async {
        let semaphore = AsyncSemaphore(limit: 2)

        let hasPermits = await semaphore.hasAvailablePermits
        #expect(hasPermits == true)
    }

    // MARK: - Wait and Signal

    @Test func waitDecrementsAvailablePermits() async throws {
        let semaphore = AsyncSemaphore(limit: 3)

        try await semaphore.wait()
        let available = await semaphore.availablePermits
        #expect(available == 2)

        try await semaphore.wait()
        let available2 = await semaphore.availablePermits
        #expect(available2 == 1)
    }

    @Test func signalIncrementsAvailablePermits() async throws {
        let semaphore = AsyncSemaphore(limit: 2)

        try await semaphore.wait()
        try await semaphore.wait()

        let beforeSignal = await semaphore.availablePermits
        #expect(beforeSignal == 0)

        await semaphore.signal()
        let afterSignal = await semaphore.availablePermits
        #expect(afterSignal == 1)
    }

    @Test func signalDoesNotExceedLimit() async {
        let semaphore = AsyncSemaphore(limit: 2)

        // Signal without any wait
        await semaphore.signal()
        await semaphore.signal()
        await semaphore.signal()

        let available = await semaphore.availablePermits
        #expect(available == 2) // Should not exceed limit
    }

    // MARK: - withPermit

    @Test func withPermitExecutesOperation() async throws {
        let semaphore = AsyncSemaphore(limit: 1)

        let result = try await semaphore.withPermit {
            42
        }

        #expect(result == 42)
    }

    @Test func withPermitReleasesOnCompletion() async throws {
        let semaphore = AsyncSemaphore(limit: 1)

        _ = try await semaphore.withPermit {
            "done"
        }

        let available = await semaphore.availablePermits
        #expect(available == 1)
    }

    @Test func withPermitReleasesOnError() async {
        struct TestError: Error {}
        let semaphore = AsyncSemaphore(limit: 1)

        do {
            _ = try await semaphore.withPermit {
                throw TestError()
            }
        } catch {
            // Expected
        }

        let available = await semaphore.availablePermits
        #expect(available == 1)
    }

    @Test func withPermitAcceptsNonThrowingWork() async throws {
        let semaphore = AsyncSemaphore(limit: 1)

        let result = try await semaphore.withPermit {
            "non-throwing"
        }

        #expect(result == "non-throwing")

        let available = await semaphore.availablePermits
        #expect(available == 1)
    }

    // MARK: - Concurrency Limiting

    @Test func limitsConcurrentExecutions() async throws {
        let semaphore = AsyncSemaphore(limit: 2)
        let tracker = ConcurrencyTracker()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0 ..< 5 {
                group.addTask {
                    try await semaphore.withPermit {
                        await tracker.start(i)
                        try? await Task.sleep(for: .milliseconds(30))
                        await tracker.end(i)
                    }
                }
            }
            try await group.waitForAll()
        }

        let maxConcurrent = await tracker.getMaxConcurrent()
        let completed = await tracker.getCompletedCount()

        #expect(maxConcurrent <= 2)
        #expect(completed == 5)
    }

    @Test func waitingCountTracksWaiters() async throws {
        let semaphore = AsyncSemaphore(limit: 1)

        // Acquire the only permit
        try await semaphore.wait()

        // Start tasks that will wait
        let waitingTasks = Task {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0 ..< 3 {
                    group.addTask {
                        try await semaphore.wait()
                    }
                }

                // Give time for tasks to start waiting
                try? await Task.sleep(for: .milliseconds(50))

                // Check waiting count
                let waiting = await semaphore.waitingCount
                #expect(waiting == 3)

                // Signal to let one through
                await semaphore.signal()
                try? await Task.sleep(for: .milliseconds(10))

                let waitingAfter = await semaphore.waitingCount
                #expect(waitingAfter == 2)

                // Clean up - signal remaining
                await semaphore.signal()
                await semaphore.signal()
                try await group.waitForAll()
            }
        }

        try await waitingTasks.value
    }

    // MARK: - FIFO Order

    @Test func resumesWaitersInFIFOOrder() async throws {
        let semaphore = AsyncSemaphore(limit: 1)
        let tracker = ConcurrencyTracker()

        // Acquire the permit
        try await semaphore.wait()

        // Start tasks that will wait in order
        let tasks = Task {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for i in 0 ..< 3 {
                    group.addTask {
                        // Small delay to ensure ordered waiting
                        try? await Task.sleep(for: .milliseconds(i * 20))
                        try await semaphore.wait()
                        await tracker.start(i)
                        await semaphore.signal()
                    }
                }
                try await group.waitForAll()
            }
        }

        // Wait for tasks to start queueing
        try? await Task.sleep(for: .milliseconds(100))

        // Release initial permit
        await semaphore.signal()

        try await tasks.value

        let events = await tracker.getEvents()
        // Tasks should start in order: 0, 1, 2
        #expect(events == ["start-0", "start-1", "start-2"])
    }

    // MARK: - Integration

    @Test func worksWithAsyncOperation() async throws {
        let semaphore = AsyncSemaphore(limit: 2)
        let tracker = ConcurrencyTracker()

        let operations = (0 ..< 5).map { i in
            AsyncOperation {
                await tracker.start(i)
                try await Task.sleep(for: .milliseconds(20))
                await tracker.end(i)
                return i
            }
            .limited(by: semaphore)
        }

        let results = try await AsyncOperation.all(operations).execute()

        let maxConcurrent = await tracker.getMaxConcurrent()
        #expect(maxConcurrent <= 2)
        #expect(results.sorted() == [0, 1, 2, 3, 4])
    }
}
