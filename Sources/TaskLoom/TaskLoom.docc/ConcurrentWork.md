# Concurrent work

Bound batch processing, share duplicate requests, and prevent outdated requests from updating UI state.

## Bound a collection transform

```swift
let thumbnails = try await photos.concurrentMap(maxConcurrency: 4) {
    try await makeThumbnail(for: $0)
}
```

The limit must be positive. The result preserves input order, including optional values, while at most four child tasks execute transforms. Failure cancels remaining children; parent cancellation stops further scheduling. Structured concurrency still waits for children to finish, so transforms must cooperate with cancellation.

When each element only performs work and produces no result, use `concurrentForEach(maxConcurrency:_:)`. It applies the same limit, failure, and cancellation rules without collecting outputs.

## Share one flight per key

Use `SingleFlight` when several callers may ask for the same thing at once:

```swift
let profiles = SingleFlight<User.ID, Profile>()

let profile = try await profiles.run(key: userID) {
    try await api.fetchProfile(userID)
}
```

The first caller for a key starts a flight. Callers that arrive while it runs wait for the same result, and their closures are not called. When the flight finishes, the key is cleared and every waiter receives the same value or the same error. Nothing is cached, so the next call starts a new flight. Different keys run independently.

A cancelled waiter throws `CancellationError` immediately and stops waiting; the others keep waiting. The flight's work is cancelled only when every waiter has cancelled, and the key is then cleared so the next call starts fresh. The operation must cooperate with cancellation to stop promptly.

## Deliver only the latest request

Keep a `LatestTask` coordinator on the main actor:

```swift
@MainActor
final class SearchModel {
    private let search = LatestTask()
    var results: [String] = []

    func update(query: String) {
        search.submit(operation: {
            try await searchService(query)
        }, onCompletion: { [weak self] result in
            if case .success(let values) = result {
                self?.results = values
            }
        })
    }
}
```

Submitting cancels the previous request and creates a new generation. Only the current generation can deliver a result, even if earlier work ignores cancellation. Completion runs synchronously on the main actor, keeping the generation check and state update together. Ordinary failures are delivered as `Result.failure`; cancelled or superseded work does not deliver results.

`cancel()` invalidates pending delivery immediately. The returned task handle can be awaited for actual completion. `isRunning` describes the current request, not any superseded work still finishing. Keep the coordinator alive for the requests it coordinates; avoid strong capture cycles in long-running closures. The operation closure is Sendable and the utility does not promise a background thread.
