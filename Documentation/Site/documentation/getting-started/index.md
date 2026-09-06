---
title: "Getting started \u00b7 TaskLoom"
description: "Composable task orchestration for Swift concurrency, with Combine and Dispatch utilities."
---

Installation

# Your first operation.

TaskLoom requires Swift 6.3. Apple deployment targets start at iOS 18, macOS 15, tvOS 18, watchOS 11, and visionOS 2. The portable concurrency surface also supports Linux.

## Add the package

Add this dependency to your Swift package, or enter the repository URL in Xcode's package dependency dialog. Until the first tagged release, select the main branch; pin a commit for reproducible builds.

```swift
.package(url: "https://github.com/modern-swift-dev/taskloom-swift.git", branch: "main")
```

Add the library product to your target's dependencies:

```swift
.product(name: "TaskLoom", package: "taskloom-swift")
```

## Compose and execute

```swift
import TaskLoom

let value = try await AsyncOperation.just(21)
    .map { $0 * 2 }
    .execute()
```

The operation is lazy. `map` transforms its result, and `execute` starts it. Use `AsyncTask` for closures that cannot throw.

## Choose the next guide

Learn about [retry and timeout ordering](/docs/taskloom-swift/api/taskloom/documentation/taskloom/cancellationandretries/), or explore [task ownership and lifetimes](/docs/taskloom-swift/api/taskloom/documentation/taskloom/tasklifetimes/). Combine helpers and the serial queue are available only where Combine can be imported.
