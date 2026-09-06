import Foundation
@testable import TaskLoom
import Testing

/// Actor for tracking execution state in a thread-safe manner
private actor ExecutionTracker {
    var attemptCount = 0
    var executedValues: [String] = []
    var errors: [any Error] = []

    func recordAttempt() {
        attemptCount += 1
    }

    func recordValue(_ value: String) {
        executedValues.append(value)
    }

    func recordError(_ error: any Error) {
        errors.append(error)
    }

    func getAttemptCount() -> Int {
        attemptCount
    }

    func getExecutedValues() -> [String] {
        executedValues
    }

    func getErrors() -> [any Error] {
        errors
    }
}

private struct TestError: Error, Equatable {
    let message: String
    init(_ message: String = "test error") {
        self.message = message
    }
}

@Suite(.serialized) struct AsyncOperationTests {

    // MARK: - Basic Execution

    @Test func operationExecutesSuccessfully() async throws {
        let result = try await AsyncOperation { "success" }.execute()
        #expect(result == "success")
    }

    @Test func operationExecutesAsyncWork() async throws {
        let result = try await AsyncOperation {
            try await Task.sleep(for: .milliseconds(10))
            return 42
        }.execute()

        #expect(result == 42)
    }

    @Test func operationPropagatesError() async {
        do {
            _ = try await AsyncOperation<Int> {
                throw TestError("expected")
            }.execute()
            Issue.record("Expected error to be thrown")
        } catch let error as TestError {
            #expect(error.message == "expected")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - Timeout

    @Test func timeoutSucceedsWhenOperationCompletesFast() async throws {
        let result = try await AsyncOperation {
            try await Task.sleep(for: .milliseconds(10))
            return "fast"
        }
        .timeout(.milliseconds(500))
        .execute()

        #expect(result == "fast")
    }

    @Test func timeoutFailsWhenOperationIsSlow() async {
        do {
            _ = try await AsyncOperation {
                try await Task.sleep(for: .seconds(10))
                return "slow"
            }
            .timeout(.milliseconds(50))
            .execute()
            Issue.record("Expected timeout error")
        } catch let error as AsyncOperationError {
            if case .timeout = error {
                // Expected
            } else {
                Issue.record("Expected timeout error, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - Retry

    @Test func retrySucceedsOnFirstAttempt() async throws {
        let tracker = ExecutionTracker()

        let result = try await AsyncOperation {
            await tracker.recordAttempt()
            return "success"
        }
        .retry(3)
        .execute()

        #expect(result == "success")
        let attempts = await tracker.getAttemptCount()
        #expect(attempts == 1)
    }

    @Test func retrySucceedsAfterFailures() async throws {
        let tracker = ExecutionTracker()

        let result = try await AsyncOperation {
            await tracker.recordAttempt()
            let count = await tracker.getAttemptCount()
            if count < 3 {
                throw TestError("fail \(count)")
            }
            return "success on attempt 3"
        }
        .retry(5)
        .execute()

        #expect(result == "success on attempt 3")
        let attempts = await tracker.getAttemptCount()
        #expect(attempts == 3)
    }

    @Test func retryFailsAfterMaxAttempts() async {
        let tracker = ExecutionTracker()

        do {
            _ = try await AsyncOperation<String> {
                await tracker.recordAttempt()
                throw TestError("always fails")
            }
            .retry(3)
            .execute()
            Issue.record("Expected error after max retries")
        } catch let error as AsyncOperationError {
            if case let .maxRetriesExceeded(attempts, _) = error {
                #expect(attempts == 3)
            } else {
                Issue.record("Expected maxRetriesExceeded, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }

        let attempts = await tracker.getAttemptCount()
        #expect(attempts == 3)
    }

    @Test func retryWithBackoffDelays() async throws {
        let tracker = ExecutionTracker()
        let startTime = ContinuousClock.now

        _ = try await AsyncOperation {
            await tracker.recordAttempt()
            let count = await tracker.getAttemptCount()
            if count < 3 {
                throw TestError()
            }
            return "success"
        }
        .retry(3, backoff: .constant(.milliseconds(50)))
        .execute()

        let elapsed = startTime.duration(to: ContinuousClock.now)
        // Should have at least 100ms of delay (2 retries * 50ms)
        #expect(elapsed >= .milliseconds(80))
    }

    // MARK: - Fallback

    @Test func fallbackNotUsedOnSuccess() async throws {
        let result = try await AsyncOperation { "primary" }
            .fallback { "fallback" }
            .execute()

        #expect(result == "primary")
    }

    @Test func fallbackUsedOnFailure() async throws {
        let result = try await AsyncOperation<String> {
            throw TestError()
        }
        .fallback { "fallback" }
        .execute()

        #expect(result == "fallback")
    }

    @Test func fallbackWithConstantValue() async throws {
        let result = try await AsyncOperation<String> {
            throw TestError()
        }
        .fallback("default")
        .execute()

        #expect(result == "default")
    }

    // MARK: - Chaining

    @Test func mapTransformsResult() async throws {
        let result = try await AsyncOperation { 5 }
            .map { $0 * 2 }
            .execute()

        #expect(result == 10)
    }

    @Test func flatMapChainsOperations() async throws {
        let result = try await AsyncOperation { 5 }
            .flatMap { value in
                AsyncOperation { value * 3 }
            }
            .execute()

        #expect(result == 15)
    }

    // MARK: - Lifecycle Hooks

    @Test func onSuccessCalledOnSuccess() async throws {
        let tracker = ExecutionTracker()

        let result = try await AsyncOperation { "value" }
            .onSuccess { await tracker.recordValue($0) }
            .execute()

        #expect(result == "value")
        let values = await tracker.getExecutedValues()
        #expect(values == ["value"])
    }

    @Test func onSuccessNotCalledOnFailure() async {
        let tracker = ExecutionTracker()

        _ = try? await AsyncOperation<String> { throw TestError() }
            .onSuccess { await tracker.recordValue($0) }
            .execute()

        let values = await tracker.getExecutedValues()
        #expect(values.isEmpty)
    }

    @Test func onFailureCalledOnError() async {
        let tracker = ExecutionTracker()

        _ = try? await AsyncOperation<String> { throw TestError("oops") }
            .onFailure { await tracker.recordError($0) }
            .execute()

        let errors = await tracker.getErrors()
        #expect(errors.count == 1)
    }

    @Test func onFailureNotCalledOnSuccess() async throws {
        let tracker = ExecutionTracker()

        _ = try await AsyncOperation { "success" }
            .onFailure { await tracker.recordError($0) }
            .execute()

        let errors = await tracker.getErrors()
        #expect(errors.isEmpty)
    }

    @Test func onCompletionCalledOnSuccess() async throws {
        let tracker = ExecutionTracker()

        let result = try await AsyncOperation { "done" }
            .onCompletion { result in
                if case let .success(value) = result {
                    await tracker.recordValue(value)
                }
            }
            .execute()

        #expect(result == "done")
        let values = await tracker.getExecutedValues()
        #expect(values == ["done"])
    }

    @Test func onCompletionCalledOnFailure() async {
        let tracker = ExecutionTracker()

        _ = try? await AsyncOperation<String> { throw TestError("completion") }
            .onCompletion { result in
                if case let .failure(error) = result {
                    await tracker.recordError(error)
                }
            }
            .execute()

        let errors = await tracker.getErrors()
        #expect((errors.first as? TestError)?.message == "completion")
    }

    @Test func checkCancellationSucceedsWhenTaskIsActive() async throws {
        let result = try await AsyncOperation { "active" }
            .checkCancellation()
            .execute()

        #expect(result == "active")
    }

    @Test func checkCancellationThrowsWhenTaskIsCancelled() async throws {
        let task = Task {
            try await AsyncOperation { "cancelled" }
                .checkCancellation()
                .execute()
        }

        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    // MARK: - Static Constructors

    @Test func justReturnsValue() async throws {
        let result = try await AsyncOperation.just(42).execute()
        #expect(result == 42)
    }

    @Test func failThrowsError() async {
        do {
            _ = try await AsyncOperation<Int>.fail(TestError("fail")).execute()
            Issue.record("Expected error")
        } catch is TestError {
            // Expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Race

    @Test func raceReturnsFirstToComplete() async throws {
        let result = try await AsyncOperation.race([
            AsyncOperation {
                try await Task.sleep(for: .milliseconds(100))
                return "slow"
            },
            AsyncOperation {
                try await Task.sleep(for: .milliseconds(10))
                return "fast"
            }
        ]).execute()

        #expect(result == "fast")
    }

    @Test func raceAgainstReturnsFirstToComplete() async throws {
        let result = try await AsyncOperation {
            try await Task.sleep(for: .milliseconds(50))
            return "slow"
        }
        .race(against: AsyncOperation { "fast" })
        .execute()

        #expect(result == "fast")
    }

    // MARK: - All

    @Test func allCollectsAllResults() async throws {
        let results = try await AsyncOperation.all([
            AsyncOperation { 1 },
            AsyncOperation { 2 },
            AsyncOperation { 3 }
        ]).execute()

        #expect(results == [1, 2, 3])
    }

    @Test func allPreservesOrder() async throws {
        let results = try await AsyncOperation.all([
            AsyncOperation {
                try await Task.sleep(for: .milliseconds(30))
                return "a"
            },
            AsyncOperation {
                try await Task.sleep(for: .milliseconds(10))
                return "b"
            },
            AsyncOperation {
                try await Task.sleep(for: .milliseconds(20))
                return "c"
            }
        ]).execute()

        #expect(results == ["a", "b", "c"])
    }

    // MARK: - AllSettled

    @Test func allSettledIgnoresFailures() async throws {
        let results = try await AsyncOperation.allSettled([
            AsyncOperation { 1 },
            AsyncOperation<Int> { throw TestError() },
            AsyncOperation { 3 }
        ]).execute()

        #expect(results == [1, 3])
    }

    // MARK: - Composability

    @Test func complexChainWorks() async throws {
        let tracker = ExecutionTracker()

        let result = try await AsyncOperation {
            await tracker.recordAttempt()
            let count = await tracker.getAttemptCount()
            if count < 2 {
                throw TestError()
            }
            return 10
        }
        .retry(3, backoff: .constant(.milliseconds(10)))
        .timeout(.seconds(1))
        .map { $0 * 2 }
        .onSuccess { _ in await tracker.recordValue("success") }
        .execute()

        #expect(result == 20)
        let attempts = await tracker.getAttemptCount()
        #expect(attempts == 2)
        let values = await tracker.getExecutedValues()
        #expect(values == ["success"])
    }

    @Test func tracedReturnsSuccessfulResult() async throws {
        let result = try await AsyncOperation { "traced" }
            .traced("Test.swift", "tracedReturnsSuccessfulResult()", 1)
            .execute()

        #expect(result == "traced")
    }

    @Test func tracedRethrowsFailure() async {
        await #expect(throws: TestError.self) {
            _ = try await AsyncOperation<String> { throw TestError("traced") }
                .traced("Test.swift", "tracedRethrowsFailure()", 1)
                .execute()
        }
    }
}
