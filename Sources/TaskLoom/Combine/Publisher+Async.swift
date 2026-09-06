#if canImport(Combine)
import Combine
import Foundation

public extension Publisher where Output: Sendable, Failure == Never {

    /// Returns the first value from a publisher that emits synchronously on subscription.
    ///
    /// The subscription is not retained. Delayed publishers (including publishers
    /// using `receive(on:)` or `subscribe(on:)`) can leave this call suspended forever.
    /// Empty completion and task cancellation do not resume this method.
    /// Use Combine's `values` async sequence for asynchronous publishers.
    func single() async -> Self.Output {
        await withCheckedContinuation { continuation in
            _ = first().sink(receiveValue: { output in
                continuation.resume(returning: output)
            })
        }
    }
}

public extension Publisher where Output: Sendable {

    /// Returns the first value from a publisher that emits synchronously on subscription.
    ///
    /// The subscription is not retained. Delayed publishers (including publishers
    /// using `receive(on:)` or `subscribe(on:)`) can leave this call suspended forever.
    /// Empty completion and task cancellation do not resume this method.
    /// Use Combine's `values` async sequence for asynchronous publishers.
    func single() async throws -> Self.Output {
        try await withCheckedThrowingContinuation { continuation in
            _ = first()
                .sink(
                    receiveCompletion: { completion in
                        if case let .failure(error) = completion {
                            continuation.resume(throwing: error)
                        }
                    },
                    receiveValue: { output in
                        continuation.resume(returning: output)
                    }
                )
        }
    }

}

#endif
