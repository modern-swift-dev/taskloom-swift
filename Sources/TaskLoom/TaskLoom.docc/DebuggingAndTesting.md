# Debugging and testing

Name operations, inspect their lifecycle, and advance time explicitly in tests.

## Trace an execution

```swift
let recorder = OperationTraceRecorder(recordsEvents: true)
let value = try await AsyncOperation { try await loadUser() }
    .retry(3)
    .traced("Load user", recorder: recorder)
    .execute()
let events = await recorder.events()
```

Each execution has a distinct ID, source location, and elapsed duration. Nested traced operations inherit a parent ID and recorder through task-local context. Place `traced` after retry and concurrency policies to include their events within that execution. The free function `withOperationTrace(name:operation:)` also wraps ordinary async code.

Tracing emits SwiftLog metadata without recording result values or error messages. Events describe start, retry, permit waiting/acquisition/cancelled waits, cancellation requests, and success or failure. A failure event leaves the original thrown error unchanged.

`activeOperations()` returns snapshots of explicitly traced work, including its elapsed time, permit wait state, and whether cancellation was requested. It does not enumerate every Swift task. Cancellation requests do not remove work from the snapshot: an operation stays active until it actually finishes, even if it ignores cancellation.

History retention is disabled by default. Enable it for a scoped debugging session or a test; retained history is unbounded. `waitForEvent(matching:)` waits for a retained or future milestone and supports cancellation. Without retained history, it only observes future events.

## Control time in tests

Add the `TaskLoomTesting` product to your test target and import it to use `ManualClock`.

```swift
let clock = ManualClock()
let task = Task {
    try await AsyncOperation { try await loadUser() }
        .retry(3, backoff: .constant(.seconds(5)), clock: clock)
        .execute()
}

// Arrange loadUser to fail its first attempt before this milestone.
try await clock.waitUntilSleeping()
clock.advance(by: .seconds(5))
let user = try await task.value
```

Advancing time resumes registered sleepers whose deadlines have passed. It does not wait for resumed work to finish or schedule another sleep. Wait for each expected milestone before advancing again. Clock waits and milestone waits respond to cancellation. Tracing elapsed durations use `ContinuousClock`, independently of the injected scheduling clock.
