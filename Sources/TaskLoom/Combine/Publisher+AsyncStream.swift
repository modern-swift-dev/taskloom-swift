#if canImport(Combine)
import Combine
import Foundation

public extension Publisher where Failure == Never {

    /// Transform a publisher that publishes multiple events into an non-throwing AsyncStream, allowing to easily
    /// bridge the combine code with async-await code
    func iterate(_ over: (Self.Output) async -> Bool) async {
        for await value in self.values {
            let shouldContinue = await over(value)
            if !shouldContinue {
                break
            }
        }
    }
}

public extension Publisher {

    /// Transform a publisher that publishes multiple events into an throwing AsyncStream, allowing to easily
    /// bridge the combine code with async-await code
    func iterate(_ over: (Self.Output) async throws -> Bool) async throws {
        for try await value in self.values {
            let shouldContinue = try await over(value)
            if !shouldContinue {
                break
            }
        }
    }
}

#endif
