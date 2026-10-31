# `AsyncOperationSerialQueue` is redesigned under the same name

The queue keeps its name but becomes cross-platform: no Combine dependency, operations run in the caller's context instead of being forced onto the main actor, and `enqueue` is awaited and returns the operation's result or rethrows its error. `Progress`, the `global` singleton, the unused `applyTestRestriction` parameter, and the `Cancellable` conformance are removed. A caller's cancellation skips its operation if not yet started, or propagates into it if running. `cancelAll()` fails every waiter with `CancellationError`, cancels the running operation, and leaves the queue usable. Enqueuing onto the same queue from inside one of its operations would deadlock, so it is detected with a task-local and stops with `preconditionFailure`.

## Consequences

Keeping the name means existing callers compile against a type whose `enqueue` now suspends until the work finishes; the changelog must call this out. Fire-and-forget callers wrap the call in `Task { try await queue.enqueue { … } }`.
