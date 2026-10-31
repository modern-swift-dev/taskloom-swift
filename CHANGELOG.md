# Changelog

All notable changes to TaskLoom are documented here. Before 1.0, minor releases may contain breaking changes; each is listed under **Breaking** with its replacement. Decisions behind breaking changes are recorded in [`docs/adr/`](docs/adr/).

## Unreleased

### Breaking

- Removed the unused `swift-async-algorithms` and `swift-collections` dependencies. If you relied on them transitively, add them to your own package.
- Removed `Publisher.single()`. Replace it with `for try await value in publisher.values { ... }`, or `for await value in publisher.values { ... }` when `Failure == Never`.
- Removed `AsyncOperationError.cancelled`. Cancellation is always reported as Swift's `CancellationError`; remove any `case .cancelled` matches.
- `AsyncOperationError` no longer conforms to `Equatable`. Match with `if case`, for example `if case .timedOut = error as? AsyncOperationError { ... }`.
- Replaced `retry(_:backoff:when:)` with `retry(_:backoff:decide:)`, whose closure returns a `RetryDecision` (`.stop`, `.retry`, `.retry(after:)`) so a failure can choose the delay. Before: `.retry(3, when: { isTransient($0) })`. After: `.retry(3, decide: { isTransient($0) ? .retry : .stop })`.
- Replaced `AsyncOperationError.timeout(Duration)` with the payload-free `AsyncOperationError.timedOut`, thrown by both the duration and deadline forms. Before: `if case let .timeout(duration) = error { ... }`. After: `if case .timedOut = error { ... }`. See [ADR 0006](docs/adr/0006-timeouts-throw-timedout.md).
- Redesigned `AsyncOperationSerialQueue` as an actor available on every platform, including Linux. `enqueue(_:)` now suspends until the operation finishes and returns its value or rethrows its error; operations are no longer forced onto the main actor. Fire-and-forget callers use `Task { try await queue.enqueue { ... } }`. A caller cancelled before its turn is skipped, cancellation of a running operation is forwarded to it, and the new `cancelAll()` does both for every caller while keeping the queue usable. Enqueuing onto the same queue from inside one of its operations stops with a precondition failure. Removed `progress`, `completedTaskCount`, `remainingTaskCount`, `fractionCompleted`, `totalTaskCount`, `refreshCount()`, `static let global`, the `priority` and `applyTestRestriction` initializer parameters, the `file`, `function`, and `line` parameters of `enqueue`, the `Cancellable` conformance with `cancel()` and `store(in:)`, the `enqueueCancellable` variants, and `flush()` (await `enqueue` instead). See [ADR 0007](docs/adr/0007-serial-queue-redesign.md).

### Added

- Added `AsyncOperation.firstSuccess(_:)`, which returns the first operation to succeed and cancels the rest. If every operation fails it throws the new `AsyncOperationError.allFailed([any Error])`, with errors in input order.
- Added deadline timeouts: `AsyncOperation.timeout(until:clock:)` and a `ContinuousClock` convenience `timeout(until:)`, so several steps can share one cut-off, plus the matching `AsyncTask.timeout(until:clock:default:)`. A deadline that has already passed times out immediately without starting the work.
- Added `Collection.concurrentForEach(maxConcurrency:_:)`, which runs a throwing body for every element with the same concurrency limit, failure, and cancellation rules as `concurrentMap`, without collecting results.
- Added `SingleFlight`, an actor that deduplicates concurrent work by key: callers that arrive while a flight is running share its value or error instead of starting their own. A cancelled caller stops waiting immediately; the work is cancelled only when every caller has cancelled. Nothing is cached once the flight finishes.
- Added `RateLimiter`, an actor-based token bucket for "N per period" limits, with `AsyncOperation.limited(by:)` and `AsyncTask.limited(by:)` overloads that take a token before each execution. The bucket starts full with `burst` tokens and refills continuously at `rate / period`. Waiters are served in arrival order; a cancelled waiter throws `CancellationError` without consuming a token. Inject a clock with `init(rate:per:burst:clock:)`; `waitingCount` reports queued callers. Traced operations report the wait as `waitingForPermit`.
