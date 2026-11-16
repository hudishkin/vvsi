# VVSI lint rules

Target API: **unreleased after 0.2.0-alpha.1** (this checkout). Apply to every agent-authored VVSI feature. IDs are stable; eval scenarios cite them.

Severity:

- `error` — fail the eval / reject the diff.
- `warning` — allow only with a one-line comment that names the exception.

Detection is heuristic on purpose: a future script can grep these; an agent can self-check the same list.

---

## Files and shape

### L1 — Three-file feature form `error`

A new screen is `Feature.swift` + `Feature+State.swift` + `Feature+Interactor.swift`. Helpers may be `Feature+Methods.swift`. Do not dump state, actions, and Interactor into the View file.

### L2 — Nest under `extension FeatureName` `error`

`VState`, `VAction`, `VEvent`, and `Interactor` live in `extension FeatureName`. No free-floating `ProfileState` types.

### L3 — Adapter matches the deployment target `error`

iOS 17+ / macOS 14+ / tvOS 17+: `@State private var viewState = ObservableViewState(...)`. Older targets: `@StateObject private var viewState = ViewState(...)`. Do not mix in one feature. Do not start requests in `Interactor.init`: `@State` evaluates the initializer on every parent rebuild.

### L4 — Feature View is `@MainActor` `error`

Both adapters are MainActor-isolated. The feature `View` and tests that construct it must be `@MainActor`.

---

## State, actions, events

### L5 — View never writes `viewState.state` `error`

Read `viewState.state` in `body`. Write only through `trigger`. Ban `viewState.state =` and `viewState.state.x =`.

### L6 — One-shot UI is `VEvent`, not state flags `error`

Ban `showAlert`, `alertMessage`, `toast`, `hud` on `VState`. Alerts/toasts map in the View from `onReceive(viewState.events)` or `eventStream()` into local `@State`.

### L7 — No dummy lifecycle actions `error`

Ban `VAction` cases named `stop`, `cancel`, `onDisappear`, `resetLoading` whose only job is to clear leftover flags. Loading is `viewState.isWorking`; other leftover state is `didCancel` after `viewState.cancel()`, or a Work `updater`.

### L8 — No completion callbacks on actions `error`

Ban closures / continuations on `VAction` (e.g. `case load(() -> Void)`). Await `trigger(action)?.finish()` from `.task` / `.refreshable`.

### L9 — High-frequency values stay in View `@State` `warning`

Slider, drag, text-while-typing do not become an action per tick. Promote to `VAction` on commit (Search, Save, slider `onEditingChanged` false).

---

## reduce and Work

### L10 — Sync actions return `nil` `error`

If `reduce` does not start I/O, persistence, a timer, or heavy CPU, it returns `nil`. Do not wrap sync work in `Task` or `Work`.

### L11 — I/O returns a plain `Work` `error`

Load / refresh / search / save return `Work { }`. That replaces the previous work. Do not add a string, `WorkKey`, or `policy:`. Use `Work(.dropWhileRunning)` only to ignore a duplicate of that same slot. Use `Work(.concurrent)` only when the operation must keep running beside the slot.

### L12 — No work identifiers `error`

Do not introduce `WorkKey`, `cancel(key:)`, or a string whose job is to group work. There is one slot. Two operations that must both stay running are `Work(.concurrent)` and are cancelled by the handle `trigger` returned.

### L13 — Async mutations only through `updater` `error`

Inside Work, ban writing captured `state` copies. Use `await updater { $0... }`. Inside `reduce`, mutate `inout state` directly — do not call `updater` there.

### L14 — Capture dependencies in the Work closure `error`

`[events, service]` (or the injected function) must be captured explicitly. Do not close over `self` of the Interactor unless `self` is Sendable and intended.

### L15 — Cooperative cancel before success and before events `error`

After `await` in Work:

```swift
try Task.checkCancellation()
await updater { ... }
```

In `catch`:

```swift
guard !Task.isCancelled else { return }
events.send(.error(...))
```

Cancellation does not retract events already sent.

### L16 — Loading comes from `isWorking` `error`

Ban `isLoading`, `isRefreshing`, and similar spinner flags on `VState` for slot work. The View reads `viewState.isWorking`, which the runtime keeps on through replacement and turns off on completion or any cancellation. `Work(.concurrent)` is not covered: its spinner is a `VState` flag cleared by `updater` on completion and by a sync action next to `handle.cancel()`. A domain flag that `reduce` must read (for example `isSubmitting` guarding a counter, see L18) stays in `VState`; clear it through `updater` and, if any View calls `viewState.cancel()`, in `didCancel`. Never clear it from an *old* work’s cancel path when a replacement may already be running.

### L17 — Know what does *not* call `didCancel` `error`

`didCancel` runs only after `viewState.cancel()`. It does **not** run for `handle.cancel()`, a replaced `Work`, `.dropWhileRunning`, or `finish()`. Agent code that resets flags in `didCancel` for a single cancelled handle is wrong.

### L18 — `dropWhileRunning` still runs `reduce` `error`

If a second trigger is dropped, the synchronous reduction has already happened. Do not increment counters, append items, or toggle one-shot flags in `reduce` before returning droppable work unless you first guard `if state.isInFlight { return nil }`.

### L19 — Work body is not MainActor; `reduce` is `warning`

Networking and CPU stay in Work. `state()` / `updater` hop to MainActor. Do not mark the Work operation `@MainActor` “to be safe”.

### L20 — Updater expires with Work `error`

For callback APIs, keep the operation alive until the callback (continuation). Do not `return` from Work after only registering a callback. Late updater calls are ignored; do not add a dummy action to “finish later”.

---

## View wiring

### L21 — Appear/refresh await `finish()` `error`

```swift
.task { await viewState.trigger(.load)?.finish() }
.refreshable { await viewState.trigger(.refresh)?.finish() }
```

Ignoring the handle is fine for button taps. It is not fine when SwiftUI should cancel that work with the task.

### L22 — `cancel()` only when ViewState outlives the screen `warning`

A ViewState owned by the disappearing view is released and already cancels work. Call `viewState.cancel()` when the owner is a tab / parent / shared object. Implement `didCancel` if you call `cancel()` and `VState` has domain flags from L16.

### L23 — Selective stop uses the handle `error`

A “stop search” / “stop feed” control keeps the `WorkHandle` from `trigger` and calls `handle.cancel()`. The operation is `Work(.concurrent)` when other work must keep running. `viewState.cancel()` stops every work.

### L24 — No business logic in the View `error`

View maps UI → `trigger` and events → local UI state. No URLSession, no decoding, no limit rules, no retry policy in `body`.

### L25 — Dependencies enter through Interactor `init` `error`

Inject a `Sendable` function, actor, or value type. Ban process-wide singletons for fetch/save in new features. Tests must be able to replace the dependency without rendering a View. Canonical shape: `RemoteView.Interactor(fetchProducts:)`.

---

## Tests

### L26 — Feature tests do not render SwiftUI `error`

Drive `ViewState` + Interactor. Assert `state`, `eventStream()`, and `WorkOutcome`.

### L27 — No sleep-based synchronization `error`

Use injected gates / immediate fakes / `finish()`. Ban `Task.sleep` as the way to wait for load (clocks in *library* tests are out of scope).

### L28 — Cover the triangle when Work exists `warning`

If you added I/O: success, failure (preserve useful state + event), cancel-before-start (`finish() == .cancelled`, loader not called). See `RemoteExampleTests`.

---

## Self-check (agent)

Before finishing a VVSI diff, answer every line:

- [ ] L1–L4 files / adapter / MainActor
- [ ] L5–L8 no View writes, no alert flags, no dummy actions, no action callbacks
- [ ] L10–L13 sync `nil`, plain `Work`, updater-only async mutations
- [ ] L15–L18 cancel checks, `didCancel` vs keyed cancel, drop+reduce
- [ ] L21 / L24 / L25 `finish()`, no View logic, injected deps
- [ ] `swift test` (and example tests if examples changed)

Any `error` left open = do not ship the diff. Fix the skill text if the agent failed the same rule twice.
