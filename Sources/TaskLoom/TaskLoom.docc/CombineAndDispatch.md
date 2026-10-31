# Combine and Dispatch

Use the platform bridges alongside the portable concurrency APIs.

## Availability

Combine helpers and `AsyncOperationSerialQueue` are guarded by `canImport(Combine)` and are not available on Linux. Dispatch helpers are guarded by `canImport(Dispatch)`. Keep platform-specific call sites behind matching conditional compilation checks when sharing application code.

## Publishers and tasks

The publisher extensions include asynchronous iteration with `iterate`, `Future.asynchronous` for wrapping async work, and receive/subscribe scheduler conveniences. Choose the overload matching the publisher's failure type, and retain any returned cancellation token for as long as the subscription is needed.

To read values from an asynchronous publisher, use its `values` sequence directly: `for try await value in publisher.values { ... }`, or `for await value in publisher.values { ... }` when `Failure == Never`. `publisher.values` is Combine's API, not a TaskLoom extension.

`iterate` uses the publisher's asynchronous `values` sequence and stops when your handler returns `false`. `Future.asynchronous` starts its task when the future is created. Cancelling a downstream subscription does not cancel that task; use it for bounded work whose ownership is deliberate.

Task cancellation can be stored with other Combine subscriptions through `eraseToAnyCancellable()`. Releasing the token requests cancellation of the wrapped task; the task still needs to cooperate. Task-group lifetimes remain scoped to their task-group closure: do not retain a group or its cancellation wrapper beyond that scope.

Scheduler helpers such as `receiveOnMain()` select a Dispatch queue. Scheduler selection does not provide a compiler-checked main-actor guarantee. Use an explicit actor hop when crossing into actor-isolated code.

`Notification.Name` conveniences include posting through `NotificationCenter.default` and creating a publisher on Combine platforms. These preserve NotificationCenter's delivery behavior; they do not add actor isolation or automatically move notifications to another queue.

## Dispatch conveniences

`DispatchQueue.background`, `.low`, `.normal`, `.high`, and `.animation` map to global queues with background, utility, default, user-initiated, and user-interactive quality of service. They do not create private queues or change the isolation of Swift tasks. Use these conveniences when integrating an existing Dispatch-based API.
