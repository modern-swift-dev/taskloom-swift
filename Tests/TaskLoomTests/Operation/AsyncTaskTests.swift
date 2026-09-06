import Foundation
@testable import TaskLoom
import Testing

/// Actor for tracking execution state in a thread-safe manner
private actor ExecutionTracker {
    var completionCount = 0
    var executedValues: [String] = []

    func recordCompletion() {
        completionCount += 1
    }

    func recordValue(_ value: String) {
        executedValues.append(value)
    }

    func getCompletionCount() -> Int {
        completionCount
    }

    func getExecutedValues() -> [String] {
        executedValues
    }
}

@Suite(.serialized) struct AsyncTaskTests {

    // MARK: - Basic Execution

    @Test func taskExecutesSuccessfully() async {
        let result = await AsyncTask { "success" }.execute()
        #expect(result == "success")
    }

    @Test func taskExecutesAsyncWork() async {
        let result = await AsyncTask {
            try? await Task.sleep(for: .milliseconds(10))
            return 42
        }.execute()

        #expect(result == 42)
    }

    // MARK: - Timeout

    @Test func timeoutReturnsResultWhenFast() async {
        let result = await AsyncTask {
            try? await Task.sleep(for: .milliseconds(10))
            return "fast"
        }
        .timeout(.milliseconds(500), default: "timeout")
        .execute()

        #expect(result == "fast")
    }

    @Test func timeoutReturnsDefaultWhenSlow() async {
        let result = await AsyncTask {
            try? await Task.sleep(for: .seconds(10))
            return "slow"
        }
        .timeout(.milliseconds(50), default: "timeout")
        .execute()

        #expect(result == "timeout")
    }

    // MARK: - Rate Limiting

    @Test func limitedBySemaphore() async throws {
        let semaphore = AsyncSemaphore(limit: 2)
        let tracker = ExecutionTracker()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0 ..< 5 {
                group.addTask {
                    _ = try await AsyncTask {
                        await tracker.recordValue("start-\(i)")
                        try? await Task.sleep(for: .milliseconds(20))
                        await tracker.recordCompletion()
                        return i
                    }
                    .limited(by: semaphore)
                    .execute()
                }
            }
            try await group.waitForAll()
        }

        let completions = await tracker.getCompletionCount()
        #expect(completions == 5)
    }

    // MARK: - Lifecycle Hooks

    @Test func onCompleteCalledWithResult() async {
        let tracker = ExecutionTracker()

        let result = await AsyncTask { "value" }
            .onComplete { await tracker.recordValue($0) }
            .execute()

        #expect(result == "value")
        let values = await tracker.getExecutedValues()
        #expect(values == ["value"])
    }

    // MARK: - Transformation

    @Test func mapTransformsResult() async {
        let result = await AsyncTask { 5 }
            .map { $0 * 2 }
            .execute()

        #expect(result == 10)
    }

    @Test func flatMapChainsTask() async {
        let result = await AsyncTask { 5 }
            .flatMap { value in
                AsyncTask { value * 3 }
            }
            .execute()

        #expect(result == 15)
    }

    // MARK: - Static Constructors

    @Test func justReturnsValue() async {
        let result = await AsyncTask.just(42).execute()
        #expect(result == 42)
    }

    // MARK: - Race

    @Test func raceReturnsFirstToComplete() async {
        let result = await AsyncTask.race([
            AsyncTask {
                try? await Task.sleep(for: .milliseconds(100))
                return "slow"
            },
            AsyncTask {
                try? await Task.sleep(for: .milliseconds(10))
                return "fast"
            }
        ]).execute()

        #expect(result == "fast")
    }

    // MARK: - All

    @Test func allCollectsResults() async {
        let results = await AsyncTask.all([
            AsyncTask { 1 },
            AsyncTask { 2 },
            AsyncTask { 3 }
        ]).execute()

        #expect(results == [1, 2, 3])
    }

    @Test func allPreservesOrder() async {
        let results = await AsyncTask.all([
            AsyncTask {
                try? await Task.sleep(for: .milliseconds(30))
                return "a"
            },
            AsyncTask {
                try? await Task.sleep(for: .milliseconds(10))
                return "b"
            },
            AsyncTask {
                try? await Task.sleep(for: .milliseconds(20))
                return "c"
            }
        ]).execute()

        #expect(results == ["a", "b", "c"])
    }

    // MARK: - Conversion

    @Test func toOperationConverts() async throws {
        let operation = AsyncTask { 42 }.toOperation()
        let result = try await operation.execute()
        #expect(result == 42)
    }

    @Test func operationToTaskWithDefaultOnFailure() async {
        struct TestError: Error {}

        let task = AsyncOperation<Int> { throw TestError() }
            .toTask(default: 99)

        let result = await task.execute()
        #expect(result == 99)
    }

    @Test func operationToTaskWithDefaultClosure() async {
        struct TestError: Error {}

        let task = AsyncOperation<Int> { throw TestError() }
            .toTask { 42 }

        let result = await task.execute()
        #expect(result == 42)
    }

    @Test func operationToTaskSucceedsWithoutDefault() async {
        let task = AsyncOperation<Int> { 100 }
            .toTask(default: 0)

        let result = await task.execute()
        #expect(result == 100)
    }
}
