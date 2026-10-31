import Foundation

/// What `AsyncOperation.retry` should do after an attempt fails.
///
/// Return a decision from the `decide` closure so the failure itself can choose the delay,
/// for example to honor a server-provided `Retry-After` header.
///
/// ```swift
/// let user = try await AsyncOperation { try await api.fetchUser(id) }
///     .retry(3, backoff: .exponential(base: .milliseconds(100)), decide: { error in
///         switch error {
///             case let error as RateLimited: .retry(after: error.retryAfter)
///             case is NotFound: .stop
///             default: .retry
///         }
///     })
///     .execute()
/// ```
///
/// Cancellation is never retried, whatever the closure would return.
public enum RetryDecision: Sendable {
    /// Rethrow the error without making another attempt.
    case stop
    /// Make another attempt after sleeping exactly `after`, or after the ``BackoffStrategy``
    /// delay when `after` is `nil`. Prefer ``retry`` for the latter.
    case retry(after: Duration?)

    /// Make another attempt after the delay chosen by the ``BackoffStrategy``.
    ///
    /// Swift does not allow an enum to declare both `case retry` and `case retry(after:)`, so this is
    /// a static property for `.retry(after: nil)`.
    public static var retry: RetryDecision {
        .retry(after: nil)
    }
}
