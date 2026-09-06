# ``TaskLoom``

Compose asynchronous work, manage task lifetimes, and bridge Swift concurrency with Combine.

## Overview

TaskLoom contains the asynchronous utilities extracted from SwiftLibs. Its operation types are lazy: configuration creates a value, and execution starts the work. Combine conveniences and the main-actor serial queue are available only on platforms that provide Combine.

## Topics

### Guides

- <doc:GettingStarted>
- <doc:CancellationAndRetries>
- <doc:TaskLifetimes>
- <doc:CombineAndDispatch>
- <doc:DebuggingAndTesting>
- <doc:ConcurrentWork>

### Composable work

- ``AsyncOperation``
- ``AsyncTask``
- ``AsyncOperationError``
- ``BackoffStrategy``
- ``AsyncSemaphore``
- ``LatestTask``
- ``OperationTraceRecorder``
- ``OperationTraceEvent``
- ``OperationTraceSnapshot``
