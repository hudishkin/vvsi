# Changelog

All notable changes to VVSI are documented in this file.

The project follows [Semantic Versioning](https://semver.org/). During the `0.x` development phase, minor versions may contain source-breaking changes.

## [Unreleased]

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
