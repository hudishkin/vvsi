---
name: vvsi
description: >-
  Scaffolds SwiftUI features with VVSI (View-ViewState-Interactor): state, actions,
  events, and Interactor side effects. Use when adding a VVSI screen or feature,
  creating ViewState/Interactor, wiring trigger/onReceive, or when the user mentions
  VVSI, ViewState, EventPipe, or unidirectional SwiftUI architecture.
---

# VVSI Feature Scaffolding

VVSI is a thin unidirectional layer for SwiftUI: **View** displays state and sends actions, **ViewState** owns state, and **Interactor** synchronously reduces actions and optionally returns async `Work`. Ephemeral UI (alerts, toasts) goes through **events**, not state flags.

Requires VVSI **0.2+**.

## When scaffolding a feature

Create three files next to each other:

1. `FeatureName.swift` — SwiftUI `View` + `@StateObject` `ViewState`
2. `FeatureName+State.swift` — `VState`, `VAction`, `VEvent`
3. `FeatureName+Interactor.swift` — `Interactor` conforming to `ViewStateInteractorProtocol`

Optional: `FeatureName+Methods.swift` for networking/helpers as an `Interactor` extension.

Use templates in [templates.md](templates.md).

## Rules

- Mutate `inout state` directly in `reduce`; mutate async results only through `await updater { ... }`. Never assign `viewState.state` from the View.
- Return `Work` for networking, persistence, timers, and CPU-heavy processing. Return `nil` for synchronous actions.
- Synchronous actions allocate no task. Async work follows its `WorkPolicy`.
- Prefer cancellation-aware awaits when using `cancel()` (`Task.checkCancellation()`, `try await Task.sleep`).
- Use `VEvent` + `onReceive(viewState.events)` (or a lazily requested `eventStream()`) for one-shot UI events.
- Keep the View free of business logic: map UI events to `viewState.trigger(.action)`.
- Call `viewState.cancel()` on disappear when all in-flight work should stop.
- `reduce` is `MainActor`-isolated; the body of `Work` is not.
- Use `.cancelPrevious(key)` when stale results must not win, `.dropWhileRunning(key)` for duplicate suppression, and `.concurrent` only for independent work.
- Split large screens into focused View/ViewState pairs. Keep high-frequency intermediate UI values in local `@State`.
- Nest types under `extension FeatureName`.

## ViewState wiring

```swift
// With explicit initial state
@StateObject private var viewState = ViewState(.init(...), Interactor())

// Or when Interactor conforms to InitialStateProtocol
@StateObject private var viewState = ViewState(Interactor())

// Previews / tests: inject a fake Interactor
ViewState(.init(...), FakeInteractor())
```

```swift
viewState.trigger(.load)
// ...
.onReceive(viewState.events) { event in
    switch event { /* update local @State for alerts/toasts */ }
}
.onDisappear { viewState.cancel() }
```

For async consumption, create the stream when the consumer starts. Each call is an independent subscription with a newest-one buffer by default:

```swift
for await event in viewState.eventStream() {
    // Handle event.
}
```

## Interactor shape

```swift
let events = EventPipe<N>()

@MainActor
func reduce(_ state: inout S, _ action: A) -> Work<S>? {
    switch action {
    case .increment:
        state.count += 1
        return nil

    case .load:
        state.isLoading = true
        return Work(policy: .cancelPrevious("load")) { [events] _, updater in
            do {
                let value = try await service.load()
                try Task.checkCancellation()
                await updater {
                    $0.value = value
                    $0.isLoading = false
                }
            } catch is CancellationError {
                return
            } catch {
                await updater {
                    $0.isLoading = false
                }
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
- [ ] Sync actions return `nil`; async actions return `Work` with an explicit policy
- [ ] View calls `trigger` / `onReceive(events)` / `cancel` as needed
- [ ] Async work updates state only through `await updater`
