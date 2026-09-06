#if canImport(Combine)
import Combine
import Foundation
@testable import TaskLoom
import Testing

@Suite(.serialized) struct PublisherAsyncTests {

    // MARK: - single() for Non-Throwing Publishers

    @Test func singleReturnsFirstValue() async {
        let publisher = Just(42)

        let result = await publisher.single()

        #expect(result == 42)
    }

    @Test func singleReturnsFirstValueFromSequence() async {
        let publisher = [1, 2, 3, 4, 5].publisher

        let result = await publisher.single()

        #expect(result == 1)
    }

    @Test func singleWorksWithDeferredPublisher() async {
        // Use Deferred to create a publisher that emits when subscribed
        let publisher = Deferred {
            Just("Hello")
        }

        let result = await publisher.single()

        #expect(result == "Hello")
    }

    @Test func singleWorksWithCurrentValueSubject() async {
        let subject = CurrentValueSubject<Int, Never>(100)

        let result = await subject.single()

        #expect(result == 100)
    }

    @Test func singleWorksWithMappedPublisher() async {
        let publisher = Just(10)
            .map { $0 * 2 }

        let result = await publisher.single()

        #expect(result == 20)
    }

    // MARK: - single() for Throwing Publishers

    @Test func singleThrowingReturnsValue() async throws {
        let publisher = Just(42)
            .setFailureType(to: Error.self)

        let result = try await publisher.single()

        #expect(result == 42)
    }

    @Test func singleThrowingPropagatesError() async {
        struct TestError: Error, Equatable {}

        let publisher = Fail<Int, TestError>(error: TestError())

        do {
            _ = try await publisher.single()
            Issue.record("Expected error to be thrown")
        } catch is TestError {
            // Expected
        } catch {
            Issue.record("Expected TestError but got \(error)")
        }
    }

    @Test func singleThrowingWorksWithTryMap() async throws {
        let publisher = Just(10)
            .tryMap { value -> Int in
                value * 3
            }

        let result = try await publisher.single()

        #expect(result == 30)
    }

    @Test func singleThrowingPropagatesTryMapError() async {
        struct MapError: Error {}

        let publisher = Just(10)
            .tryMap { _ -> Int in
                throw MapError()
            }

        do {
            _ = try await publisher.single()
            Issue.record("Expected error to be thrown")
        } catch is MapError {
            // Expected
        } catch {
            Issue.record("Expected MapError but got \(error)")
        }
    }

    // MARK: - iterate() for Non-Throwing Publishers

    @Test func iterateProcessesAllValues() async {
        let values = [1, 2, 3, 4, 5]
        let publisher = values.publisher
        var collected: [Int] = []

        await publisher.iterate { value in
            collected.append(value)
            return true
        }

        #expect(collected == values)
    }

    @Test func iterateStopsEarlyWhenReturningFalse() async {
        let values = [1, 2, 3, 4, 5]
        let publisher = values.publisher
        var collected: [Int] = []

        await publisher.iterate { value in
            collected.append(value)
            return value < 3 // Stop after collecting 3
        }

        #expect(collected == [1, 2, 3])
    }

    @Test func iterateHandlesEmptyPublisher() async {
        let publisher = Empty<Int, Never>()
        var iterationCount = 0

        await publisher.iterate { _ in
            iterationCount += 1
            return true
        }

        #expect(iterationCount == 0)
    }

    @Test func iterateWorksWithDeferredSequence() async {
        // Use a deferred sequence publisher
        let publisher = Deferred {
            [1, 2, 3].publisher
        }

        var collected: [Int] = []
        await publisher.iterate { value in
            collected.append(value)
            return true
        }

        #expect(collected == [1, 2, 3])
    }

    // MARK: - iterate() for Throwing Publishers

    @Test func iterateThrowingProcessesAllValues() async throws {
        let values = [1, 2, 3]
        let publisher = values.publisher
            .setFailureType(to: Error.self)
        var collected: [Int] = []

        try await publisher.iterate { value in
            collected.append(value)
            return true
        }

        #expect(collected == values)
    }

    @Test func iterateThrowingStopsEarlyWhenReturningFalse() async throws {
        let values = [1, 2, 3, 4, 5]
        let publisher = values.publisher
            .setFailureType(to: Error.self)
        var collected: [Int] = []

        try await publisher.iterate { value in
            collected.append(value)
            return value < 2
        }

        #expect(collected == [1, 2])
    }

    @Test func iterateThrowingPropagatesError() async {
        struct StreamError: Error {}

        // Use a publisher that emits values then fails
        let publisher = [1, 2].publisher
            .setFailureType(to: StreamError.self)
            .append(Fail(error: StreamError()))

        var collected: [Int] = []
        do {
            try await publisher.iterate { value in
                collected.append(value)
                return true
            }
            Issue.record("Expected error to be thrown")
        } catch is StreamError {
            // Expected - error was propagated
            #expect(collected == [1, 2])
        } catch {
            Issue.record("Expected StreamError but got \(error)")
        }
    }

    // MARK: - Future.asynchronous()

    @Test
    @MainActor func futureAsynchronousReturnsResult() async {
        let publisher = Future<Int, Error>.asynchronous {
            42
        }

        var result: Int?
        var cancellable: AnyCancellable?

        await withCheckedContinuation { continuation in
            cancellable = publisher.sink(
                receiveCompletion: { _ in continuation.resume() },
                receiveValue: { result = $0 }
            )
        }

        _ = cancellable // Keep alive

        #expect(result == 42)
    }

    @Test
    @MainActor func futureAsynchronousPropagatesError() async {
        struct AsyncError: Error {}

        let publisher = Future<Int, AsyncError>.asynchronous {
            throw AsyncError()
        }

        var didReceiveError = false
        var cancellable: AnyCancellable?

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            cancellable = publisher.sink(
                receiveCompletion: { completion in
                    if case .failure = completion {
                        didReceiveError = true
                    }
                    continuation.resume()
                },
                receiveValue: { _ in }
            )
        }

        _ = cancellable

        #expect(didReceiveError)
    }

    @Test
    @MainActor func futureAsynchronousExecutesAsyncCode() async {
        let publisher = Future<String, Error>.asynchronous {
            try? await Task.sleep(for: .milliseconds(10))
            return "async result"
        }

        var result: String?
        var cancellable: AnyCancellable?

        await withCheckedContinuation { continuation in
            cancellable = publisher.sink(
                receiveCompletion: { _ in continuation.resume() },
                receiveValue: { result = $0 }
            )
        }

        _ = cancellable

        #expect(result == "async result")
    }

    // MARK: - Sendable Conformance

    @Test func singleWorksWithSendableTypes() async {
        struct SendableValue: Sendable, Equatable {
            let value: Int
        }

        let publisher = Just(SendableValue(value: 42))

        let result = await publisher.single()

        #expect(result == SendableValue(value: 42))
    }
}

#endif
