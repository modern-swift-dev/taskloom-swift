# Contributing to TaskLoom

TaskLoom is preparing its first public release. Bug reports should include the Swift/Xcode version, platform, a minimal reproduction, and the expected cancellation or scheduling behavior.

## Development

Use Swift 6.3 or newer, as specified in `Package.swift`. Apple-only Combine and serial-queue APIs need an Apple SDK. Linux validates the portable concurrency and Dispatch surface. Website development uses Node.js 22 (at least 22.12) and npm, matching CI.

```sh
swift build
swift test
```

Keep changes focused. Add Swift Testing coverage for behavior changes, particularly cancellation, early completion, retry counts, and actor isolation. Prefer controlled continuations or synchronization over timing-sensitive sleeps. Never silence concurrency warnings or disable failing tests to get a green build.

## Documentation

Public APIs should explain their actor isolation, cancellation behavior, and ownership requirements. Put conceptual guides in `Sources/TaskLoom/TaskLoom.docc`; the `Website` directory contains the Astro landing page and documentation navigation.

```sh
make site-setup
npm run check --prefix Website
make site-build
make site-check
make site-preview
make documentation
```

`make site-build` builds Astro, generates static DocC under `api/taskloom`, and checks internal links before replacing `docs`. It needs Swift, the DocC plugin, Node.js, and installed website dependencies. `make documentation` uses the DocC plugin to create a zipped TaskLoom archive for release automation. Run documentation builds on macOS with Xcode selected to include the Apple-only APIs.

Do not commit `.build`, `Website/node_modules`, or `Website/dist`. The documentation workflow commits generated `docs` to the main branch. Configure GitHub Pages to deploy from the `main` branch's `/docs` directory. Edit documentation sources rather than generated pages. No release API lookup is necessary to build the website.

## Pull requests

Explain the problem, resulting behavior, and validation performed. Highlight changes to public API or task lifetimes. Keep SwiftLibs compatibility changes separate from additional API design. Contributions are provided under the repository's MIT license.
