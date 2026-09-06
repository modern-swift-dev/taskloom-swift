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

Use `map` to transform a result and `flatMap` to select subsequent work. `all` runs operations concurrently and preserves their input order in the resulting array. `allSettled` omits failed operations; it does not return failure records.

## Limit concurrent work

Share an ``AsyncSemaphore`` between operations and apply `limited(by:)` to each one. This bounds simultaneous work; it is not a requests-per-second rate limiter. Choose a positive permit count and keep the protected work asynchronous so waiting does not block a thread. Waiting for a permit is currently not cancellation-aware: cancelling a waiting task does not remove it from the semaphore's wait queue.

See <doc:CancellationAndRetries> before composing timeout, retry, race, and fallback policies.
