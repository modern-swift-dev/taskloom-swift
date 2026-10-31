# Remove `Publisher.single()`

The inherited `single()` helpers suspend forever for publishers that emit asynchronously, complete empty, or are cancelled, because they neither retain the subscription nor observe task cancellation. Combine's `publisher.values` already handles subscription lifetime and cancellation, so we remove `single()` before 1.0 rather than maintain a corrected copy. This breaks the SwiftLibs name-compatibility promise, which we treat as best-effort before 1.0.
