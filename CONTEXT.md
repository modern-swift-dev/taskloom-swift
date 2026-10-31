# TaskLoom

Composable task orchestration for Swift concurrency: lazy units of async work that are combined, limited, and traced before they run.

## Language

### Units of work

**Operation**:
A lazy, reusable unit of async work that can fail. Each execution runs the work again.
_Avoid_: job, promise, future

**Task**:
A lazy, reusable unit of async work that cannot fail; a timed-out task resolves to a default value. Distinct from Swift's `Task`, which is work already running.
_Avoid_: infallible operation

**Attempt**:
One execution of an operation within a retry. The first execution counts as an attempt.
_Avoid_: try, retry count

**Settled result**:
The success or failure of one operation, kept as a value instead of thrown.
_Avoid_: outcome

### Coordination

**Permit**:
The right to proceed, granted by a semaphore or rate limiter and held while the limited work runs.
_Avoid_: lock, slot, ticket

**Waiter**:
A caller suspended until it receives a permit, its turn on a serial queue, or a shared flight's result.
_Avoid_: subscriber, listener

**Flight**:
The single in-progress execution shared by every waiter for one key of a `SingleFlight`. It ends when the work finishes; nothing is cached.
_Avoid_: request, in-flight request

**Superseded request**:
Work replaced by a newer submission to a `LatestTask`. Its result is never delivered.
_Avoid_: stale request, outdated request

### Diagnostics

**Trace**:
The recorded lifecycle of a named operation, linked to the operation that started it.
_Avoid_: log
