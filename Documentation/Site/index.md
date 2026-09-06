---
title: "Composable task orchestration \u00b7 TaskLoom"
description: "Composable task orchestration for Swift concurrency, with Combine and Dispatch utilities."
---

Swift 6.3 · Open source · Prerelease

# Give asynchronous work
a little structure.

Compose operations, control concurrency, and connect existing Combine and Dispatch code. TaskLoom brings the asynchronous utilities from SwiftLibs into one focused Swift package.

[Get started](/docs/taskloom-swift/documentation/getting-started/)[Explore the API](/docs/taskloom-swift/api/taskloom/documentation/taskloom/)

```swift
import TaskLoom

let operation = AsyncOperation {
    try Task.checkCancellation()
    return 42
}
.retry(3, backoff: .exponential(base: .milliseconds(100)))
.timeout(.seconds(5))

let value = try await operation.execute()
```

Nothing runs until `execute()`. Each execution starts fresh. Here, the timeout surrounds the entire retry sequence.

## Compose work

Lazy operations, result transformations, retry and backoff, fallback, races, and ordered concurrent results.

## Own the lifetime

Concurrency limits and main-actor task helpers make task ownership explicit.

## Bridge your code

Combine iteration and scheduler helpers, cancellation tokens, serial main-actor work, and Dispatch conveniences.

## Cancellation stays cooperative

A timeout requests cancellation; task groups wait for their children to finish. Operations should use cancellation-aware suspension points and checks. Read the [cancellation guide](/docs/taskloom-swift/api/taskloom/documentation/taskloom/cancellationandretries/) before composing policies.

## Ready to explore, preparing to release

Install from the main branch while the first release is being prepared. The API is still evolving. The concurrency core supports Apple platforms and Linux; Combine utilities and the serial queue require Combine.
