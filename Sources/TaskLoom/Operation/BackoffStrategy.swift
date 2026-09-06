import Foundation

/// Defines strategies for calculating delay between retry attempts.
public enum BackoffStrategy: Sendable {
    /// No delay between retries.
    case none
    /// Constant delay between each retry.
    case constant(Duration)
    /// Linearly increasing delay: base * (attempt + 1).
    case linear(base: Duration)
    /// Exponentially increasing delay: base * 2^attempt, with optional maximum cap.
    case exponential(base: Duration, max: Duration? = nil)
    /// Exponential backoff with random jitter to prevent thundering herd.
    case exponentialWithJitter(base: Duration, max: Duration? = nil)
    /// Custom delay calculation based on attempt number (0-indexed).
    case custom(@Sendable (Int) -> Duration)

    /// Calculates the delay duration for a given retry attempt.
    /// - Parameter attempt: The zero-indexed attempt number (0 = first retry).
    /// - Returns: The duration to wait before the next attempt.
    public func delay(for attempt: Int) -> Duration {
        switch self {
            case .none:
                return .zero

            case let .constant(duration):
                return duration

            case let .linear(base):
                return base * (attempt + 1)

            case let .exponential(base, max):
                let delay = base * (1 << attempt) // 2^attempt
                if let max {
                    return min(delay, max)
                }
                return delay

            case let .exponentialWithJitter(base, max):
                let baseDelay = base * (1 << attempt)
                let cappedDelay = max.map { min(baseDelay, $0) } ?? baseDelay
                // Add random jitter between 0% and 100% of the delay
                let jitterFactor = Double.random(in: 0.0 ... 1.0)
                return cappedDelay * jitterFactor

            case let .custom(calculator):
                return calculator(attempt)
        }
    }
}

// MARK: - Convenience Initializers

public extension BackoffStrategy {
    /// Creates an exponential backoff strategy with common defaults.
    /// - Parameters:
    ///   - base: Base delay duration. Defaults to 100 milliseconds.
    ///   - max: Maximum delay cap. Defaults to 30 seconds.
    /// - Returns: An exponential backoff strategy.
    static func exponentialDefault(
        base: Duration = .milliseconds(100),
        max: Duration = .seconds(30)
    ) -> BackoffStrategy {
        .exponential(base: base, max: max)
    }

    /// Creates a backoff strategy with fixed delays for each attempt.
    /// - Parameter delays: Array of delays for each attempt. Last delay is reused for additional attempts.
    /// - Returns: A custom backoff strategy.
    static func fixed(_ delays: [Duration]) -> BackoffStrategy {
        guard !delays.isEmpty else {
            return .none
        }
        return .custom { attempt in
            delays[min(attempt, delays.count - 1)]
        }
    }
}

// MARK: - Duration Multiplication

private extension Duration {
    static func * (lhs: Duration, rhs: Int) -> Duration {
        let (seconds, attoseconds) = lhs.components
        let totalAttoseconds = Int128(seconds) * 1_000_000_000_000_000_000 + Int128(attoseconds)
        let multiplied = totalAttoseconds * Int128(rhs)
        let newSeconds = multiplied / 1_000_000_000_000_000_000
        let newAttoseconds = multiplied % 1_000_000_000_000_000_000
        return Duration(secondsComponent: Int64(newSeconds), attosecondsComponent: Int64(newAttoseconds))
    }

    static func * (lhs: Duration, rhs: Double) -> Duration {
        let (seconds, attoseconds) = lhs.components
        let totalNanoseconds = Double(seconds) * 1_000_000_000 + Double(attoseconds) / 1_000_000_000
        let multiplied = totalNanoseconds * rhs
        return .nanoseconds(Int64(multiplied))
    }
}
