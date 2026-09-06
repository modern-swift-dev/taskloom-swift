# Task lifetimes

Keep ownership explicit when creating and retaining asynchronous work.

## Main-actor helpers

`UITask` starts a main-actor task. `DelayedTask` waits before invoking a main-actor handler. `RepeatingTask` waits between iterations and continues while its handler returns `true`; returning `false` ends the loop. All return a Swift task handle that the owner can retain and cancel.

These helpers create unstructured tasks. Their lifetime is not automatically tied to the calling function or view. Avoid unintended strong captures in long-lived closures. Cancellation cannot forcibly stop a handler that has already begun.

## Serial main-actor work

On Combine platforms, `AsyncOperationSerialQueue` executes accepted operations one at a time on the main actor. Retain the queue, submit asynchronous handlers, and cancel it when the owner is finished. Cancellation tokens from `enqueueCancellable` must also be retained; releasing an `AnyCancellable` cancels it.

The queue offers progress counters and `flush()`. Public submission schedules asynchronous sends, so do not assume concurrent submission calls establish a total order based on their call sites. A flush sentinel waits for work ahead of it in the channel. Cancellation can release a flush waiter without completing every submitted operation. The queue is not a background CPU executor and does not interrupt synchronous code inside a running handler.
