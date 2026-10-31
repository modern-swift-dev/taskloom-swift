# TaskLoom ships composition primitives only

TaskLoom is a public, general-purpose library for composing and limiting async work. Stream operators (debounce, throttle, channels), caching, circuit breakers, and job scheduling are out of scope. We remove the declared-but-unused `swift-async-algorithms` and `swift-collections` dependencies instead of growing into them: users who want stream operators add AsyncAlgorithms themselves, and it composes with TaskLoom without glue.

## Consequences

Within scope for 1.0: request deduplication (`SingleFlight`), a cross-platform serial queue, `firstSuccess`, error-driven retry delays, deadlines, `concurrentForEach`, and a token-bucket `RateLimiter`. Heterogeneous `race`/`all` are left to `async let`.
