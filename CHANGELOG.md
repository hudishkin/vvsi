# Changelog

All notable changes to VVSI are documented in this file.

The project follows [Semantic Versioning](https://semver.org/). During the `0.x` development phase, minor versions may contain source-breaking changes.

## [Unreleased]

### Fixed

- Work no longer retains either ViewState adapter across suspension; releasing the owner requests cancellation.
- Cancelled, replaced, and completed work cannot apply late updates through escaped callbacks or other tasks.
- Awaiting cancelled-before-start or dropped work always resolves, including pull-to-refresh.
- Example list items use stable identities; the example package reference no longer depends on the checkout directory name.

### Added

- `WorkHandle.finish()` / `cancel()` and `WorkOutcome` for explicit work lifetimes and SwiftUI task integration.
- `isWorking` on both adapters: a runtime-owned loading indicator. It turns on in `trigger`, stays on while one `Work` replaces another, and turns off on completion or any cancellation, including `.task` cancellation and handles cancelled off the main thread. `.concurrent` work is excluded.
- Optional `Interactor.didCancel` resets non-loading state after `viewState.cancel()`, so screens do not need a dummy `.stop` action.
- Shared lifecycle regression tests for both observation adapters and injectable remote example requests.
- CI checks for Swift 5/6 language modes, a build on the oldest available toolchain (Xcode 16.0), minimum platform deployment targets, and executed example tests. Swift 5.9 and 5.10 remain supported but are no longer verified in CI.

### Changed

- `Work { }` replaces the previous work. Load and refresh share that slot, so there is no key to mistype.
- `.dropWhileRunning` and `.concurrent` no longer take an identifier. Concurrent work stays outside the slot and is cancelled through its handle.
- Both adapters share one internal work runner and are fully MainActor-isolated.
- Cancellation invalidates updates and resolves handles promptly; underlying operations still cancel cooperatively.
- `CurrentState` retains the last committed snapshot after owner release, without retaining the owner.
- `ObservableViewState` is no longer experimental and is the recommended adapter on iOS 17+ / macOS 14+ / tvOS 17+. `ViewState` remains for older targets.
- Examples await work handles instead of callback continuations, and show loading from `isWorking` instead of a `VState` flag.

### Breaking

- Creating/reading ViewState and conforming to `ViewStateProtocol` now requires MainActor isolation.
- Custom `ViewStateProtocol` conformers must return `WorkHandle?` from `trigger` and provide `isWorking`.
- Removed `WorkKey`, string work keys, and `cancel(key:)`. The default policy is `.cancelPrevious`, not `.concurrent`.
- Leftover cleanup after a full cancel is `Interactor.didCancel`, not a View-side `cancel { }` closure.
- Updaters captured by callback integrations expire when their Work returns; keep the operation alive for the callback's lifetime.

## [0.2.0-alpha.1] - 2026-08-10

### Added

- Synchronous `reduce` fast path that does not allocate a task.
- Async `Work` for side effects and background processing.
- `WorkPolicy` with concurrent, cancel-previous, and drop-while-running execution.
- Cooperative cancellation and tracked in-flight work.
- `EventPipe` with Combine publisher and lazy, bounded `AsyncStream` support.
- `InitialStateProtocol`.
- Experimental Observation-based `ObservableViewState`.
- Tests for work policies, cancellation, event delivery, and MainActor isolation.

### Changed

- Replaced `execute` with `reduce(_: _:) -> Work?`.
- Replaced notification terminology with events.
- Made state updates synchronous inside `reduce` and MainActor-isolated inside `Work`.
- Moved async `Work` execution away from `MainActor`.

### Breaking

- `NotificationProtocol` was replaced by `EventProtocol`.
- `notifications` was replaced by `events`.
- Interactors must implement synchronous `reduce` instead of `execute`.
- `CurrentState` and `StateUpdater` contracts changed.
- Events and feature state must satisfy their `Sendable` contracts.

### Known limitations

- `WorkPolicy` identifiers currently use string keys.
- Cancellation is cooperative; work must observe cancellation.
- Async `Work` can update state directly instead of sending another action through `reduce`.
- `dropWhileRunning` drops only returned work; the synchronous reduction still runs.
- Classic `ViewState` publishes the entire feature state.
- `ObservableViewState` remains experimental.

[Unreleased]: https://github.com/hudishkin/vvsi/compare/0.2.0-alpha.1...HEAD
[0.2.0-alpha.1]: https://github.com/hudishkin/vvsi/compare/0.0.5...0.2.0-alpha.1
