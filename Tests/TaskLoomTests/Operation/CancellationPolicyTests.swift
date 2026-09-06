import Foundation
@testable import TaskLoom
import Testing

@Suite struct CancellationPolicyTests {
    private enum Failure: Error { case transient, permanent }
    private actor Counter {
        var value = 0
        func increment() -> Int { value += 1; return value }
    }

    @Test func cancelledSemaphoreWaitDoesNotNeedPermit() async throws {
        let semaphore = AsyncSemaphore(limit: 1)
        try await semaphore.wait()
        let waiting = Task { try await semaphore.wait() }
        while await semaphore.waitingCount == 0 { await Task.yield() }
        waiting.cancel()
        do { try await waiting.value; Issue.record("Expected cancellation") }
        catch { #expect(error is CancellationError) }
        #expect(await semaphore.waitingCount == 0)
        #expect(await semaphore.availablePermits == 0)
        await semaphore.signal()
        #expect(await semaphore.availablePermits == 1)
    }

    @Test func cancelledAcquisitionNeverRunsWork() async {
        let semaphore = AsyncSemaphore(limit: 1)
        let ready = TestSignal()
        let counter = Counter()
        let task = Task {
            await ready.wait()
            return try await semaphore.withPermit { await counter.increment() }
        }
        task.cancel()
        await ready.signal()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch { #expect(error is CancellationError) }
        #expect(await counter.value == 0)
        #expect(await semaphore.availablePermits == 1)
    }

    @Test func cancellationRacingReleaseDoesNotLeakPermit() async throws {
        for _ in 0..<100 {
            let semaphore = AsyncSemaphore(limit: 1)
            try await semaphore.wait()
            let task = Task { try await semaphore.withPermit { 1 } }
            while await semaphore.waitingCount == 0 { await Task.yield() }
            task.cancel()
            await semaphore.signal()
            _ = await task.result
            #expect(await semaphore.availablePermits == 1)
            #expect(await semaphore.waitingCount == 0)
        }
    }

    @Test func retryRejectsPermanentErrors() async {
        let counter = Counter()
        let operation = AsyncOperation<Int> {
            _ = await counter.increment()
            throw Failure.permanent
        }.retry(4, when: { ($0 as? Failure) == .transient })
        do { _ = try await operation.execute(); Issue.record("Expected failure") }
        catch { #expect((error as? Failure) == .permanent) }
        #expect(await counter.value == 1)
    }

    @Test func cancellationErrorDoesNotRetryOrRecover() async {
        let counter = Counter()
        let operation = AsyncOperation<Int> {
            _ = await counter.increment()
            throw CancellationError()
        }.retry(4).recover { _ in
            Issue.record("Cancellation must not recover")
            return 0
        }.fallback(10)
        do { _ = try await operation.execute(); Issue.record("Expected cancellation") }
        catch { #expect(error is CancellationError) }
        #expect(await counter.value == 1)
    }

    @Test func recoveryReceivesOrdinaryFailure() async throws {
        let value = try await AsyncOperation<Int> { throw Failure.permanent }
            .recover { error in
                #expect((error as? Failure) == .permanent)
                return 42
            }.execute()
        #expect(value == 42)
    }

    @Test func allSettledPreservesOptionalSuccessAndChildCancellation() async throws {
        let results = try await AsyncOperation<Int?>.allSettled([
            AsyncOperation { nil },
            AsyncOperation { throw CancellationError() },
            AsyncOperation { 3 }
        ]).execute()
        #expect(results.count == 3)
        #expect(try results[0].get() == nil)
        if case .failure(let error) = results[1] { #expect(error is CancellationError) }
        else { Issue.record("Expected cancellation result") }
        #expect(try results[2].get() == 3)
    }
}
