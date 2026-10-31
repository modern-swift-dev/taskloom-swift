# `CancellationError` is the only cancellation signal

`AsyncOperationError.cancelled` is only thrown when a task group's `next()` returns `nil` in `timeout` and `race`, which cannot happen (timeout always adds two children; race rejects empty input). We remove the case, turn those branches into `preconditionFailure`, and treat only Swift's `CancellationError` as cancellation in `fallback`, `recover`, and `retry`. One signal is simpler for callers to match than two.
