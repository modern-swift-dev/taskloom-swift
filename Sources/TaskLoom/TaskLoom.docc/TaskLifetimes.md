# Task lifetimes

Keep ownership explicit when creating and retaining asynchronous work.

## Main-actor helpers

`UITask` starts a main-actor task. `DelayedTask` waits before invoking a main-actor handler. `RepeatingTask` waits between iterations and continues while its handler returns `true`; returning `false` ends the loop. All return a Swift task handle that the owner can retain and cancel.

These helpers create unstructured tasks. Their lifetime is not automatically tied to the calling function or view. Avoid unintended strong captures in long-lived closures. Cancellation cannot forcibly stop a handler that has already begun.

## Serial work

`AsyncOperationSerialQueue` runs operations one at a time, in the order their `enqueue` calls reach the queue. `enqueue` suspends until the operation has run and returns its value or rethrows its error. For fire-and-forget work, wrap the call in a task: `Task { try await queue.enqueue { ... } }`. Calls made one after another from the same isolation context keep their order; calls from different tasks race.

Operations are not forced onto the main actor; pass a `@MainActor` closure when the work needs it. If a caller is cancelled before its operation starts, the operation is skipped and the caller throws `CancellationError` right away. If the operation is already running, it is cancelled cooperatively, and the next operation starts only after it returns. `cancelAll()` does both for every caller and leaves the queue usable for later work.

An operation must not enqueue onto the queue that is running it, including from an unstructured `Task` it creates: that call would wait for itself, so it stops with a precondition failure. Enqueuing onto a different queue is fine. The queue does not interrupt synchronous code inside a running operation.
