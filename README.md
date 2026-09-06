# TaskLoom

Composable task orchestration for Swift concurrency, with Combine bridges and GCD conveniences.

TaskLoom extracts the asynchronous utilities from SwiftLibs into a standalone Swift package. It includes lazy operations, retries and backoff, cooperative timeouts, concurrency limits, main-actor task helpers, and publisher interoperability.

This repository is preparing its first release. The API may change before 1.0.

## Installation

Add the package to your `Package.swift`:

```swift
.package(url: "https://github.com/modern-swift-dev/taskloom-swift.git", branch: "main")
```

Then add `.product(name: "TaskLoom", package: "taskloom-swift")` to your target dependencies and `import TaskLoom`. Until a release is tagged, pin a commit for reproducible production builds.

## A first operation

```swift
import TaskLoom

let operation = AsyncOperation {
    try Task.checkCancellation()
    return "Hello from TaskLoom"
}
.retry(3, backoff: .exponential(base: .milliseconds(100)))
.timeout(.seconds(5))

let message = try await operation.execute()
```

Operations are lazy and reusable: each `execute()` runs the closure again. Here the timeout wraps the entire retry sequence; placing `timeout` before `retry` gives each attempt its own timeout. Three attempts includes the first execution.

## What is included

| Area | APIs |
| --- | --- |
| Composable work | `AsyncOperation`, `AsyncTask`, mapping, fallback, racing, ordered collection |
| Concurrency control | Cancellation-aware `AsyncSemaphore`, selective retries, `BackoffStrategy`, bounded `concurrentMap` |
| Diagnostics | Named tracing, lifecycle events, execution snapshots, source locations |
| UI coordination | `LatestTask` prevents superseded requests from delivering results |
| Testing | Injectable clocks and the `TaskLoomTesting` product with `ManualClock` |
| Task lifetimes | `UITask`, `DelayedTask`, `RepeatingTask` |
| Combine | Publisher async bridges and iteration, task cancellation tokens, scheduler shortcuts, timers, notification helpers |
| Serial work | `AsyncOperationSerialQueue` for main-actor operations, progress and cancellation |
| GCD | Named `DispatchQueue` conveniences for quality-of-service classes |

The concurrency utilities support Apple platforms and Linux. Combine APIs, cancellation-token helpers, and the serial queue are compiled only where Combine is available. Dispatch conveniences require Dispatch. See [Package.swift](Package.swift) for the supported toolchain and minimum platform versions.

## Cancellation and execution semantics

Cancellation is cooperative. Timeouts and races cancel losing child tasks, but structured task groups still wait for those children to finish. A closure that ignores cancellation can delay return beyond the configured timeout.

`AsyncOperation.race` selects the first completion, including a failure. `all` preserves input order and throws on failure; `allSettled` retains one `Result` per input, including failures, and propagates parent cancellation. `fallback` and `recover` propagate cancellation instead of recovering from it.

Semaphore `wait()` and `withPermit` throw on cancellation. Limiting an `AsyncTask` produces an `AsyncOperation`, since acquiring a permit can fail.

`UITask`, `DelayedTask`, and `RepeatingTask` run their handlers on the main actor. Keep CPU-intensive work out of those handlers. Retain task handles and cancel them when their owner no longer needs the work. A repeating handler returns `false` to stop.

## Migrating from SwiftLibs

Replace the `SLAsync` product dependency and `import SLAsync` with `TaskLoom`.
The existing async utility names are preserved. TaskLoom also includes the
`Notification.Name` posting and publisher helpers previously in `SLFoundation`;
avoid importing both modules for those overlapping extensions.

TaskLoom has no SwiftLibs dependency. Diagnostics use SwiftLog with the
`TaskLoom` label and the host application's logging backend. Creation timestamps
use the local wall clock; elapsed durations use `ContinuousClock` and no longer
depend on SwiftLibs' synchronized clock.

## Documentation and development

The [central documentation repository](https://github.com/modern-swift-dev/docs) owns Astro, the shared theme, and website/API generation. It builds from `main` daily and on manual runs. Edit page Markdown in `Documentation/Site/` and keep DocC catalogs beside the module sources. See the [docs README](https://github.com/modern-swift-dev/docs/blob/main/README.md) for local build and preview commands. Do not commit generated HTML to this repository.

Read the [DocC guides](Sources/TaskLoom/TaskLoom.docc/TaskLoom.md). `make documentation` creates `.build/documentation/TaskLoom-Documentation.zip` for Xcode and releases.

The inherited `Publisher.single()` helper currently only reliably supports synchronous emission; it does not safely manage a long-lived subscription, empty completion, or task cancellation. Prefer another bridge for asynchronous publishers until that API is revised.

See [CONTRIBUTING.md](CONTRIBUTING.md) for validation commands and contribution guidelines.

## License

TaskLoom is available under the [MIT license](LICENSE).
