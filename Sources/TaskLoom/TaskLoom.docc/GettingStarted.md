# Getting started

Build a reusable asynchronous operation and choose the policies that surround it.

## Installation

Add `https://github.com/modern-swift-dev/taskloom-swift.git` using Swift Package Manager, select the `main` branch during the prerelease period, and add the `TaskLoom` product to your target. Use `import TaskLoom` in source files. Pin a revision if you need a reproducible dependency before the first release.

## Compose an operation

```swift
import TaskLoom

let operation = AsyncOperation {
    try Task.checkCancellation()
    return 42
}
.retry(3, backoff: .constant(.milliseconds(100)))
.timeout(.seconds(2))

let result = try await operation.execute()
```

``AsyncOperation`` accepts a sendable asynchronous closure and returns a sendable result. Every execution runs the closure again. Use ``AsyncTask`` for work that returns a value without throwing. Its timeout takes a default value because failure is not part of its result type.

Use `map` to transform a result and `flatMap` to select subsequent work. `all` runs operations concurrently and preserves their input order in the resulting array. `allSettled` returns an ordered array of `Result` values, retaining failures and optional successes. Parent cancellation still throws. For bounded scheduling, use `collection.concurrentMap(maxConcurrency:)`.

## Limit concurrent work

Share an ``AsyncSemaphore`` between operations and apply `limited(by:)` to each one. This bounds simultaneous work; it is not a requests-per-second rate limiter. Choose a positive permit count and keep the protected work asynchronous so waiting does not block a thread. Both `wait()` and `withPermit` throw when cancelled. Cancelled waiters leave the queue without consuming a permit. Applying `limited(by:)` to a nonthrowing `AsyncTask` returns an `AsyncOperation` because permit acquisition can throw.

## Limit request rate

Share a ``RateLimiter`` to cap how often work starts, such as ten requests per second:

```swift
let limiter = RateLimiter(rate: 10, per: .seconds(1), burst: 10)

let user = try await AsyncOperation { try await api.fetchUser(id) }
    .limited(by: limiter)
    .execute()
```

The limiter is a token bucket. It starts full with `burst` tokens, refills continuously at `rate / period`, and never holds more than `burst`. Each execution takes one token with `acquire()`, waiting when none is available. Tokens are consumed rather than released, so a rate limiter bounds starts, not simultaneous work; combine it with an ``AsyncSemaphore`` when you need both. Waiters are served in arrival order, and a later caller never takes a token ahead of an earlier waiter. A cancelled waiter throws `CancellationError` without consuming a token. Inject a clock with `init(rate:per:burst:clock:)`, for example `ManualClock` in tests. As with the semaphore, applying `limited(by:)` to an `AsyncTask` returns an `AsyncOperation`, and traced operations report the wait as `waitingForPermit`.

See <doc:CancellationAndRetries> before composing timeout, retry, race, and fallback policies.
