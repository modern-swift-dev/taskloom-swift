# Cancellation and retries

Understand policy ordering and cooperative cancellation before composing work.

## Policy order

Modifiers wrap the operation built so far. `.retry(3).timeout(.seconds(5))` gives the whole sequence a five-second timeout. `.timeout(.seconds(5)).retry(3)` gives each attempt its own timeout. The retry count includes the initial attempt and must be positive.

``BackoffStrategy`` provides constant, linear, exponential, jittered exponential, and custom delays. Exhausted retries throw `AsyncOperationError.maxRetriesExceeded`, preserving the last error. Cancellation is checked before each attempt and before backoff. Cancellation errors never retry.

Pass a `decide:` closure that returns a ``RetryDecision`` for each failure: `.stop` rethrows the error unchanged, `.retry` waits for the backoff delay, and `.retry(after:)` waits exactly that duration instead, for example a server's `Retry-After`. Delays are slept on the `clock:` you inject, if any. Exhausting every attempt throws `maxRetriesExceeded` whatever the closure returns, and `decide` is never called for cancellation.

```swift
let user = try await AsyncOperation { try await api.fetchUser(id) }
    .retry(3, backoff: .exponential(base: .milliseconds(100)), decide: { error in
        switch error {
            case let error as RateLimited: .retry(after: error.retryAfter)
            case is NotFound: .stop
            default: .retry
        }
    })
    .execute()
```

## Cooperative timeouts

Timeouts race work against a sleeping child task. The losing child is cancelled, but the task group must wait for every child to exit. A timeout is therefore a cancellation request, not a guarantee that the function returns at a wall-clock deadline. Use cancellation-aware suspension points and `Task.checkCancellation()` in long-running work.

A timed-out operation throws `AsyncOperationError.timedOut`, whether the timeout was a duration or a deadline. `timeout(_:)` measures its duration from the start of each execution. `timeout(until:)` takes an absolute deadline instead, so several steps can share one cut-off:

```swift
let deadline = ContinuousClock.now + .seconds(10)
let user = try await fetchUser.timeout(until: deadline).execute()
let posts = try await fetchPosts(user).timeout(until: deadline).execute()
```

A deadline that has already passed times out immediately, without starting the work.

``AsyncTask`` expresses timeouts with a default value. It also accepts a deadline with `timeout(until:default:)`. It cannot throw `CancellationError` to its caller. Converting an operation with `toTask(default:)` also turns all errors, including cancellation, into the supplied default.

## Races and fallback

`AsyncOperation.race` uses the first completed result, which may be an error. It does not wait for the first success after an earlier failure. Losing child tasks are cancelled cooperatively.

`AsyncOperation.firstSuccess` waits for the first success and ignores failures before it, then cancels the remaining operations. If every operation fails, it throws `AsyncOperationError.allFailed` with the errors in input order, not completion order. Cancelling the caller throws `CancellationError`, never `allFailed`.

`fallback` and `recover` propagate `CancellationError` and the current task's cancellation state. `recover` receives ordinary errors so it can select a replacement value. `checkCancellation()` checks immediately before starting its wrapped work; it does not automatically insert checks inside your closure.

`allSettled` retains one `Result` for every input in input order. Individual child failures, including child cancellation errors, become results; cancellation of the parent cancels the group and throws. Choose `all` when an unsuccessful child must fail the overall operation.

## Injectable timing

Timeouts and retries accept `clock:` overloads. `DelayedTask` and `RepeatingTask` accept `Duration` plus `clock:`; their handlers remain on the main actor. A throwing delayed task propagates cancellation. See <doc:DebuggingAndTesting> for deterministic tests.
