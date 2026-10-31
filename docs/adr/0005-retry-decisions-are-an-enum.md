# Retry decisions are a `RetryDecision` enum

`retry` takes a closure returning `RetryDecision` (`.stop`, `.retry`, `.retry(after: Duration)`) instead of a `when:` predicate returning `Bool`. A server-provided delay such as `Retry-After` must be able to override the backoff strategy, and a single type-checked return value cannot express "retry" and "this delay" inconsistently, unlike a separate predicate plus delay closure. Cancellation is never retried, whatever the closure returns.
