import Foundation

/// Errors that can occur during async operation execution.
public enum AsyncOperationError: Error, Sendable, Equatable {
    /// The operation exceeded the specified timeout duration.
    case timeout(Duration)
    /// The operation failed after exhausting all retry attempts.
    case maxRetriesExceeded(attempts: Int, lastError: any Error)
    /// The operation was cancelled.
    case cancelled

    public static func == (lhs: AsyncOperationError, rhs: AsyncOperationError) -> Bool {
        switch (lhs, rhs) {
            case let (.timeout(lhsDuration), .timeout(rhsDuration)):
                lhsDuration == rhsDuration
            case let (.maxRetriesExceeded(lhsAttempts, _), .maxRetriesExceeded(rhsAttempts, _)):
                lhsAttempts == rhsAttempts
            case (.cancelled, .cancelled):
                true
            default:
                false
        }
    }
}

extension AsyncOperationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
            case let .timeout(duration):
                "Operation timed out after \(duration)"
            case let .maxRetriesExceeded(attempts, lastError):
                "Operation failed after \(attempts) attempts. Last error: \(lastError.localizedDescription)"
            case .cancelled:
                "Operation was cancelled"
        }
    }
}
