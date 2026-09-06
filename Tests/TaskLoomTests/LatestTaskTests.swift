import TaskLoom
import Testing

@MainActor struct LatestTaskTests {
    @Test func supersededWorkCannotDeliverEvenWhenItIgnoresCancellation() async {
        let latest = LatestTask()
        let firstStarted = TestSignal()
        let releaseFirst = TestSignal()
        var received: [Int] = []
        let first = latest.submit {
            await firstStarted.signal()
            await releaseFirst.wait()
            return 1
        } onCompletion: { result in
            if case let .success(value) = result {
                received.append(value)
            }
        }
        await firstStarted.wait()
        #expect(latest.isRunning)
        let second = latest.submit { 2 } onCompletion: { result in
            if case let .success(value) = result {
                received.append(value)
            }
        }
        await second.value
        await releaseFirst.signal()
        await first.value
        #expect(received == [2])
        #expect(!latest.isRunning)
    }

    @Test func explicitCancellationSuppressesDelivery() async {
        let latest = LatestTask()
        let started = TestSignal()
        let release = TestSignal()
        var delivered = false
        let task = latest.submit {
            await started.signal()
            await release.wait()
        } onCompletion: { _ in delivered = true }
        await started.wait()
        latest.cancel()
        #expect(!latest.isRunning)
        await release.signal()
        await task.value
        #expect(!delivered)
    }

    @Test func deliversFailureButSuppressesCancellationErrors() async {
        enum Failure: Error { case expected }
        let latest = LatestTask()
        var receivedFailure = false
        let failure = latest.submit { () throws -> Int in
            throw Failure.expected
        } onCompletion: { result in
            if case let .failure(error) = result {
                receivedFailure = error is Failure
            }
        }
        await failure.value
        #expect(receivedFailure)
        var deliveredCancellation = false
        let cancelled = latest.submit { () throws -> Int in
            throw CancellationError()
        } onCompletion: { _ in deliveredCancellation = true }
        await cancelled.value
        #expect(!deliveredCancellation)
        #expect(!latest.isRunning)
    }

    @Test func completionCanSubmitAnotherRequest() async {
        let latest = LatestTask()
        var second: Task<Void, Never>?
        var received: [Int] = []
        let first = latest.submit { 1 } onCompletion: { result in
            if case let .success(value) = result {
                received.append(value)
            }
            second = latest.submit { 2 } onCompletion: { result in
                if case let .success(value) = result {
                    received.append(value)
                }
            }
        }
        await first.value
        await second?.value
        #expect(received == [1, 2])
        #expect(!latest.isRunning)
    }
}
