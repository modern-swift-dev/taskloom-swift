# Contributing to TaskLoom

TaskLoom is preparing its first public release. Bug reports should include the Swift/Xcode version, platform, a minimal reproduction, and the expected cancellation or scheduling behavior.

## Development

Use Swift 6.3 or newer, as specified in `Package.swift`. Apple-only Combine and serial-queue APIs need an Apple SDK. Linux validates the portable concurrency and Dispatch surface.

```sh
swift build
swift test
```

Keep changes focused. Add Swift Testing coverage for behavior changes, particularly cancellation, early completion, retry counts, and actor isolation. Prefer controlled continuations or synchronization over timing-sensitive sleeps. Never silence concurrency warnings or disable failing tests to get a green build.

## Documentation

Public APIs should explain their actor isolation, cancellation behavior, and ownership requirements. Put conceptual guides in `Sources/TaskLoom/TaskLoom.docc`.

The [central documentation repository](https://github.com/modern-swift-dev/docs) owns Astro, the shared theme, and website/API generation. It builds from `main` daily and on manual runs. Edit page Markdown in `Documentation/Site/` and keep DocC catalogs beside the module sources. See the [docs README](https://github.com/modern-swift-dev/docs/blob/main/README.md) for local build and preview commands. Do not commit generated HTML to this repository.

`make documentation` creates a zipped TaskLoom archive for release automation. Run it on macOS with Xcode selected to include Apple-only APIs.

## Pull requests

Explain the problem, resulting behavior, and validation performed. Highlight changes to public API or task lifetimes. Keep SwiftLibs compatibility changes separate from additional API design. Contributions are provided under the repository's MIT license.
