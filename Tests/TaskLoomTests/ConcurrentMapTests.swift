import TaskLoom
import Testing

private actor ConcurrentMapTracker {
    private(set) var started: [Int] = []
    private(set) var active = 0
    private(set) var maximum = 0

    func start(_ value: Int) {
        started.append(value)
        active += 1
        maximum = max(maximum, active)
    }

    func finish() { active -= 1 }
}

@Suite struct ConcurrentMapTests {
    @Test func boundsWorkAndPreservesInputOrder() async throws {
        let started = (0..<4).map { _ in TestSignal() }
        let release = (0..<4).map { _ in TestSignal() }
        let tracker = ConcurrentMapTracker()
        let task = Task {
            try await Array(0..<4).concurrentMap(maxConcurrency: 2) { value in
                await tracker.start(value)
                await started[value].signal()
                await release[value].wait()
                await tracker.finish()
                return value * 10
            }
        }
        await started[0].wait()
        await started[1].wait()
        #expect(await tracker.started.sorted() == [0, 1])
        await release[1].signal()
        await started[2].wait()
        await release[2].signal()
        await started[3].wait()
        await release[3].signal()
        await release[0].signal()
        #expect(try await task.value == [0, 10, 20, 30])
        #expect(await tracker.maximum == 2)
    }

    @Test func retainsOptionalOutputsAndHandlesEmptyCollections() async throws {
        let values = try await [1, 2].concurrentMap(maxConcurrency: 10) { value -> Int? in
            value == 1 ? nil : value
        }
        #expect(values == [nil, 2])
        let empty = try await [Int]().concurrentMap(maxConcurrency: 1) { $0 }
        #expect(empty.isEmpty)
    }

    @Test func failureCancelsSiblingAndStopsScheduling() async {
        enum Failure: Error { case expected }
        let siblingStarted = TestSignal()
        let siblingCancelled = TestSignal()
        let tracker = ConcurrentMapTracker()
        do {
            _ = try await Array(0..<10).concurrentMap(maxConcurrency: 2) { value in
                await tracker.start(value)
                if value == 0 {
                    await siblingStarted.wait()
                    throw Failure.expected
                }
                await siblingStarted.signal()
                do {
                    try await Task.sleep(for: .seconds(3_600))
                } catch {
                    await siblingCancelled.signal()
                    throw error
                }
                return value
            }
            Issue.record("Expected transform failure")
        } catch {
            #expect(error is Failure)
        }
        await siblingCancelled.wait()
        #expect(await tracker.started.sorted() == [0, 1])
    }

    @Test func cancellationDoesNotScheduleMoreWork() async {
        let started = TestSignal()
        let release = TestSignal()
        let tracker = ConcurrentMapTracker()
        let task = Task {
            try await Array(0..<5).concurrentMap(maxConcurrency: 1) { value in
                await tracker.start(value)
                await started.signal()
                await release.wait() // Intentionally ignores cancellation.
                return value
            }
        }
        await started.wait()
        task.cancel()
        await release.signal()
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(await tracker.started == [0])
    }
}
