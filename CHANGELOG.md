# Changelog

All notable changes to TaskLoom are documented here. Before 1.0, minor releases may contain breaking changes; each is listed under **Breaking** with its replacement. Decisions behind breaking changes are recorded in [`docs/adr/`](docs/adr/).

## Unreleased

### Breaking

- Removed the unused `swift-async-algorithms` and `swift-collections` dependencies. If you relied on them transitively, add them to your own package.
- Removed `Publisher.single()`. Replace it with `for try await value in publisher.values { ... }`, or `for await value in publisher.values { ... }` when `Failure == Never`.
- Removed `AsyncOperationError.cancelled`. Cancellation is always reported as Swift's `CancellationError`; remove any `case .cancelled` matches.

### Added
