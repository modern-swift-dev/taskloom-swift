# Cancellation and retries

Understand policy ordering and cooperative cancellation before composing work.

## Policy order

Modifiers wrap the operation built so far. `.retry(3).timeout(.seconds(5))` gives the whole sequence a five-second timeout. `.timeout(.seconds(5)).retry(3)` gives each attempt its own timeout. The retry count includes the initial attempt and must be positive.

``BackoffStrategy`` provides constant, linear, exponential, jittered exponential, and custom delays. Exhausted retries throw `AsyncOperationError.maxRetriesExceeded`, preserving the last error. Cancellation is checked before each attempt and before backoff. Cancellation errors never retry. Use `retry(_:backoff:when:)` to select eligible failures; rejected errors propagate unchanged.

## Cooperative timeouts

Timeouts race work against a sleeping child task. The losing child is cancelled, but the task group must wait for every child to exit. A timeout is therefore a cancellation request, not a guarantee that the function returns at a wall-clock deadline. Use cancellation-aware suspension points and `Task.checkCancellation()` in long-running work.

``AsyncTask`` expresses timeouts with a default value. It cannot throw `CancellationError` to its caller. Converting an operation with `toTask(default:)` also turns all errors, including cancellation, into the supplied default.

## Races and fallback

`AsyncOperation.race` uses the first completed result, which may be an error. It does not wait for the first success after an earlier failure. Losing child tasks are cancelled cooperatively.

`fallback` and `recover` propagate `CancellationError`, `AsyncOperationError.cancelled`, and the current task's cancellation state. `recover` receives ordinary errors so it can select a replacement value. `checkCancellation()` checks immediately before starting its wrapped work; it does not automatically insert checks inside your closure.

`allSettled` retains one `Result` for every input in input order. Individual child failures, including child cancellation errors, become results; cancellation of the parent cancels the group and throws. Choose `all` when an unsuccessful child must fail the overall operation.

## Injectable timing

Timeouts and retries accept `clock:` overloads. `DelayedTask` and `RepeatingTask` accept `Duration` plus `clock:`; their handlers remain on the main actor. A throwing delayed task propagates cancellation. See <doc:DebuggingAndTesting> for deterministic tests.
