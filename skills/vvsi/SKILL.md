---
name: vvsi
version: unreleased-after-0.2.0-alpha.1
description: >-
  Scaffolds SwiftUI features with VVSI (View-ViewState-Interactor): state, actions,
  events, and Interactor side effects. Use when adding a VVSI screen or feature,
  creating ViewState/Interactor, wiring trigger/onReceive, or when the user mentions
  VVSI, ViewState, EventPipe, or unidirectional SwiftUI architecture.
---

# VVSI Feature Scaffolding

VVSI is a thin unidirectional layer for SwiftUI: **View** displays state and sends actions, **ViewState** owns state, and **Interactor** synchronously reduces actions and optionally returns async `Work`. Ephemeral UI (alerts, toasts) goes through **events**, not state flags.

Targets the **unreleased API after 0.2.0-alpha.1** in this checkout; use a local package until the next prerelease is published.

## When scaffolding a feature

Create three files next to each other:

1. `FeatureName.swift` — SwiftUI `View` + `@State` `ObservableViewState` (iOS 17+), or `@StateObject` `ViewState` for older targets
2. `FeatureName+State.swift` — `VState`, `VAction`, `VEvent`
3. `FeatureName+Interactor.swift` — `Interactor` conforming to `ViewStateInteractorProtocol`

Optional: `FeatureName+Methods.swift` for networking/helpers as an `Interactor` extension.

Use templates in [templates.md](templates.md). Before finishing a feature, self-check [lint.md](lint.md). Agent eval prompts live in [eval.md](eval.md).

## Rules

- Mutate `inout state` directly in `reduce`; mutate async results only through `await updater { ... }`. Never assign `viewState.state` from the View.
- Show loading from `viewState.isWorking`. Do not add `isLoading` to `VState`: the runtime keeps `isWorking` correct through replacement and cancellation.
- Return `Work` for networking, persistence, timers, and CPU-heavy processing. Return `nil` for synchronous actions.
- Synchronous actions allocate no task. Async work follows its `WorkPolicy`.
- Prefer cancellation-aware awaits when using `cancel()` (`Task.checkCancellation()`, `try await Task.sleep`).
- Use `VEvent` + `onReceive(viewState.events)` (or a lazily requested `eventStream()`) for one-shot UI events.
- Keep the View free of business logic: map UI events to `viewState.trigger(.action)`.
- Prefer `.task { await viewState.trigger(action)?.finish() }` so SwiftUI cancels that work when the view goes away. If ViewState survives disappear (tabs, shared owner), call `viewState.cancel()`. Implement `didCancel` only for state other than loading that a full cancel must reset. `handle.cancel()` and `finish()` do not call `didCancel`.
- ViewState and ObservableViewState are MainActor-isolated; annotate feature Views with `@MainActor`.
- Await `viewState.trigger(action)?.finish()` in `.task` / `.refreshable`. Avoid completion callbacks and manual continuations in actions.
- Updaters expire when Work completes or is cancelled. Keep callback-based work alive until its callback finishes.
- A plain `Work` replaces the previous one. There is no work key. Stop one `Work(.concurrent)` through the handle `trigger` returned; `cancel()` stops everything.
- Work cancellation does not retract already sent EventPipe events; check cancellation before sending async events.
- `reduce` is `MainActor`-isolated; the body of `Work` is not.
- Use `Work(.dropWhileRunning)` to ignore a duplicate of the single slot, and `Work(.concurrent)` only when that operation must keep running beside the slot.
- Split large screens into focused View/ViewState pairs. Keep high-frequency intermediate UI values in local `@State`.
- Nest types under `extension FeatureName`.

## ViewState wiring

```swift
// iOS 17+ / macOS 14+ / tvOS 17+
@State private var viewState = ObservableViewState(.init(...), Interactor())

// Older deployment targets
@StateObject private var viewState = ViewState(.init(...), Interactor())

// Either adapter, when Interactor conforms to InitialStateProtocol
ObservableViewState(Interactor())

// Previews / tests: inject a fake Interactor
ObservableViewState(.init(...), FakeInteractor())
```

`@State` re-evaluates the initializer on every parent rebuild and keeps the first instance. Keep `Interactor.init` cheap.

```swift
if viewState.isWorking { ProgressView() }
// ...
.task { await viewState.trigger(.load)?.finish() }
.onReceive(viewState.events) { event in
    switch event { /* update local @State for alerts/toasts */ }
}
```

For async consumption, create the stream when the consumer starts. Each call is an independent subscription with a newest-one buffer by default:

```swift
for await event in viewState.eventStream() {
    // Handle event.
}
```

## Interactor shape

Inject a `Sendable` service (or an actor) and capture it explicitly in Work:

```swift
let events = EventPipe<N>()

@MainActor
func reduce(_ state: inout S, _ action: A) -> Work<S>? {
    switch action {
    case .increment:
        state.count += 1
        return nil

    case .load:
        return Work { [events, service] _, updater in
            do {
                let value = try await service.load()
                try Task.checkCancellation()
                await updater { $0.value = value }
            } catch {
                guard !Task.isCancelled else { return }
                events.send(.error(error.localizedDescription))
            }
        }
    }
}
```

## Checklist

- [ ] `VState: StateProtocol`
- [ ] `VAction: ActionProtocol`
- [ ] `VEvent: EventProtocol`
- [ ] `Interactor` with `typealias S/A/N`, `EventPipe`, synchronous `reduce`
- [ ] Sync actions return `nil`; async actions return plain `Work` unless they opt into drop or concurrent
- [ ] View calls `trigger` / `onReceive(events)` / `cancel` as needed
- [ ] Loading comes from `viewState.isWorking`, not a `VState` flag
- [ ] `didCancel` only when ViewState can outlive the screen and non-loading state must reset
- [ ] Async work updates state only through `await updater`
- [ ] Every `error` rule in [lint.md](lint.md) is clean
