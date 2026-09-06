#if canImport(Combine)
import Combine
import Foundation

public extension Future {
    /// Creates a publisher that wraps an async throwing operation
    /// - Parameter code: An async throwing closure that returns a result
    /// - Returns: A publisher that emits the result of the async operation or fails with an error
    ///
    /// Example:
    /// ```
    /// let publisher = Future<String, Error>.asynchronous {
    ///     try await fetchDataFromServer()
    /// }
    /// ```
    @MainActor static func asynchronous<ResultType: Sendable, ErrorType: Error>(_ code: @escaping @Sendable () async throws(ErrorType) -> ResultType) -> AnyPublisher<ResultType, ErrorType> {
        Future<ResultType, ErrorType> { @MainActor promise in
            Task { @MainActor in
                do throws(ErrorType) {
                    let result = try await code()
                    promise(.success(result))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }
}

#endif
