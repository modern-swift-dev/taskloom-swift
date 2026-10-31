import Foundation

/// Errors that can occur during async operation execution.
public enum AsyncOperationError: Error, Sendable {
    /// The operation did not finish before its timeout duration elapsed or its deadline passed.
    case timedOut
    /// The operation failed after exhausting all retry attempts.
    case maxRetriesExceeded(attempts: Int, lastError: any Error)
    /// Every operation passed to `AsyncOperation.firstSuccess` failed.
    ///
    /// The errors are in the same order as the input operations, not completion order.
    case allFailed([any Error])
}

extension AsyncOperationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
            case .timedOut:
                "Operation timed out"
            case let .maxRetriesExceeded(attempts, lastError):
                "Operation failed after \(attempts) attempts. Last error: \(lastError.localizedDescription)"
            case let .allFailed(errors):
                "All \(errors.count) operations failed. Errors: \(errors.map(\.localizedDescription).joined(separator: "; "))"
        }
    }
}
