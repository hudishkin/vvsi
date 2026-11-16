# VVSI agent eval

Target API: **unreleased after 0.2.0-alpha.1** (this checkout). Pair with [SKILL.md](SKILL.md), [templates.md](templates.md), and [lint.md](lint.md).

Pass bar for every scenario:

1. Diff stays inside the named files.
2. `swift test` still passes.
3. If the example app was touched, `VVSIExampleTests` still pass.
4. Every [lint](lint.md) `error` rule is clean on the new files.
5. The scenario checklist below is all yes.

The example app targets iOS 18, so new screens use `ObservableViewState` with `@State` (lint L3). Do not add navigation, DI containers, or new library API.

## How to run

1. Fresh checkout of this repo (or a worktree).
2. Give the agent `skills/vvsi` and **one** scenario prompt. No extra architecture advice.
3. Score the diff against that scenario. One miss = fail.
4. Record: pass / fail, which lint IDs fired, which leftover flags or dummy actions appeared.

A brick is real when an agent can pass **all 10** on a cold start.

---

## 1. Scaffold a sync-only screen

**Prompt**

> Add a `Counter` SwiftUI feature under `VVSIExample/VVSIExample/Views/Counter/` using VVSI. State has `count: Int`. Actions: `increment`, `decrement`. Decrement must not go below 0; then send `VEvent.limit`. The view shows the count and two buttons. No networking.

**Must**

- Three files: `Counter.swift`, `Counter+State.swift`, `Counter+Interactor.swift`.
- Types nested under `extension Counter`.
- `reduce` mutates `inout state` and returns `nil` for both actions.
- View is `@MainActor`, uses `@State` + `ObservableViewState`, `trigger`, and `onReceive` for the limit event.
- No `Work`, no `Task` in the Interactor.

**Fail if**

- Business rules live in the View.
- A dummy `.stop` action exists.
- `viewState.state` is assigned from the View.

**Verify**

```swift
let vs = ObservableViewState(Counter.Interactor())
vs.trigger(.increment)
#expect(vs.state.count == 1)
vs.trigger(.decrement)
#expect(vs.state.count == 0)
vs.trigger(.decrement)
#expect(vs.state.count == 0)
```

---

## 2. Add async load

**Prompt**

> Add `Search` under `VVSIExample/VVSIExample/Views/Search/`. User types a query (local `@State`) and taps Search. Interactor loads results through an injected `Sendable (String) async throws -> [String]`. Stale responses must not win. Show a loading flag and an error event.

**Must**

- Query text stays in View `@State` until Search is tapped; only then `trigger(.search(query))`.
- `return Work { ... }` with no policy argument, so a newer search replaces the previous one.
- The spinner reads `viewState.isWorking`; `VState` has no `isLoading`, and there is no `didCancel`.
- `[events, search]` captured explicitly in Work.
- `try Task.checkCancellation()` before applying results.
- `guard !Task.isCancelled else { return }` before sending an error event.

**Fail if**

- `Work(.concurrent)` for the search.
- A `WorkKey`, `cancel(key:)`, or string used to group work.
- Network call starts in the View.
- Results written onto `viewState.state` from the View.
- `VState` gains `isLoading` or another spinner flag.

**Verify**

Inject a slow then fast search. Second `trigger` must replace the first, and `isWorking` stays true across the replacement. After `viewState.cancel()`, `isWorking` is false and the first result must not appear.

---

## 3. Pull-to-refresh awaits `finish()`

**Prompt**

> On `RemoteView`, keep load-on-appear and pull-to-refresh. Both must await the work handle. Do not use completion callbacks in actions.

**Must**

- `.task { await viewState.trigger(.load)?.finish() }`
- `.refreshable { await viewState.trigger(.refresh)?.finish() }`
- Both load and refresh return a plain `Work`, so either replaces the other.
- Fetch stays injected on `Interactor`.

**Fail if**

- `VAction` grows a callback / continuation case.
- `trigger` result is ignored inside `.refreshable`.
- A new dummy action is added for “refresh finished”.

**Verify**

Existing `RemoteExampleTests` still pass, including “Refresh cancellation before start always resolves the handle”.

---

## 4. One-shot UI goes through events

**Prompt**

> On `ListView`, when the user hits the 5-item limit, show an alert. Do not store `showAlert` / `alertMessage` in `VState`.

**Must**

- Limit still emits `VEvent.error`.
- Alert mapping lives in View `@State` + `onReceive(viewState.events)`.
- `reduce` for `.add` stays synchronous and returns `nil`.

**Fail if**

- `VState` gains `showError`, `errorText`, or `alert`.
- The View sets those flags back to `nil` after dismiss as “state cleanup”.

**Verify**

```swift
var events = viewState.eventStream().makeAsyncIterator()
(0..<5).forEach { _ in viewState.trigger(.add) }
viewState.trigger(.add)
#expect(viewState.state.items.count == 5)
#expect(await events.next() != nil)
```

---

## 5. Injected dependency + tests without UI

**Prompt**

> Write tests for a new `Profile` feature: load a display name from `() async throws -> String`. Cover success, failure (preserve previous name, send error event), and `cancel()` before the fetch starts.

**Must**

- Interactor `init(loadName: ...)`.
- Tests construct `ObservableViewState(state, Interactor(loadName:))` — no `View` render.
- Success: `await handle.finish() == .completed`, name set, `isWorking == false`.
- Failure: previous name kept, event received from `eventStream()`.
- Cancel-before-start: injected loader must not run; `finish() == .cancelled`; `isWorking == false`.

**Fail if**

- Tests sleep (`Task.sleep`) to “wait for loading”.
- Tests hit the network.
- Tests instantiate the SwiftUI `View`.

**Verify**

`swift test` plus the new suite. Mirror `RemoteExampleTests`.

---

## 6. Shared owner: full cancel, no dummy `.stop`

**Prompt**

> `Inbox` is shown inside a tab, so its ViewState is owned by the parent and survives disappear. On disappear, cancel in-flight work; the spinner must not stay on. Inbox also keeps a `draft: String` that must be cleared when the tab cancels its work. Do not add a `.stop` / `.cancel` action.

**Must**

- Parent owns the `ObservableViewState`; child receives it as a plain property.
- Child calls `viewState.cancel()` in `onDisappear`.
- Spinner reads `viewState.isWorking`; `VState` has no `isLoading`.
- `Interactor.didCancel` clears `draft` and nothing else.
- No `VAction.stop`.

**Fail if**

- View writes leftover state itself.
- `didCancel` or a Work `catch` touches a loading flag.
- `handle.cancel()` is used as the full-screen teardown.

**Verify**

```swift
let handle = try #require(viewState.trigger(.load))
#expect(viewState.isWorking)
viewState.cancel()
#expect(await handle.finish() == .cancelled)
#expect(!viewState.isWorking)
#expect(viewState.state.draft.isEmpty)
```

---

## 7. `dropWhileRunning` does not skip `reduce`

**Prompt**

> `Checkout` has `submit`. While a submit is running, extra taps must drop *work* but must not increment `submitCount` twice. `submitCount` is how many accepted submits happened.

**Must**

- Policy `Work(.dropWhileRunning)`.
- `submitCount += 1` only when work is actually accepted — not blindly in `reduce` before returning `Work`.
- Document or guard the pitfall: dropped work still ran `reduce` if you mutate first.

**Canonical shape**

```swift
case .submit:
    if state.isSubmitting { return nil }
    state.isSubmitting = true
    state.submitCount += 1
    return Work(.dropWhileRunning) { ... }
```

**Fail if**

- `reduce` always increments, then returns dropped work (count lies).
- Duplicate suppression is done with a View `disabled` flag only and `.concurrent` work.

**Verify**

Trigger `.submit` twice without awaiting. `submitCount == 1`, first handle completes, second is `nil` or `finish() == .dropped` without a second increment.

---

## 8. High-frequency UI stays local

**Prompt**

> `Volume` has a slider 0...1 and a Save button. Dragging the slider must not `trigger` on every tick. Save persists through an injected `Sendable (Double) async throws -> Void`.

**Must**

- Slider value is View `@State`.
- `VAction.save(Double)` only on Save (or on slider commit, once).
- Persist work is a plain `Work` or `Work(.dropWhileRunning)`. No key.

**Fail if**

- `VAction.setVolume` / `reduce` on every `Slider` tick.
- Volume is stored in `VState` *and* written on every drag.

**Verify**

A test can call `trigger(.save(0.5))` once. There is no action that represents an intermediate drag.

---

## 9. Callback API: do not let Work return early

**Prompt**

> `Location` starts a one-shot callback API `requestOnce { Result<String, Error> -> Void }` from Work. The updater must still apply after the callback. Do not add a completion case to `VAction`.

**Must**

- Work stays alive until the callback fires (continuation / `withCheckedContinuation`).
- `await updater` runs inside that lifetime.
- After `cancel()`, a late callback must not mutate state (updater is expired — do not fight this with extra flags).

**Fail if**

- Work returns immediately after registering the callback.
- Action carries a completion handler.
- View holds the callback.

**Verify**

Success path: `finish() == .completed` and state has the value. Cancel path: fire the callback after `cancel()`; state unchanged.

---

## 10. One handle cancels only its work

**Prompt**

> `Dashboard` can load `profile` and `feed` in parallel. A “Stop feed” button cancels only the feed work. Profile must keep running. Do not add a string key or `WorkKey`.

**Must**

- Both operations return `Work(.concurrent)`, so neither occupies the single slot.
- The caller keeps the feed `WorkHandle` and calls `handle.cancel()`.
- `didCancel` is **not** used for this button.
- `isWorking` does not cover `.concurrent` work, so each operation has its own `VState` flag. The Stop button calls `handle.cancel()` and triggers a sync action that clears the feed flag: the cancelled work's updater is already expired and cannot clear it.

**Fail if**

- Stop feed calls `viewState.cancel()` and kills profile.
- A `WorkKey`, `cancel(key:)`, or string identifier appears.
- Either operation uses the default slot, so starting one replaces the other.

**Verify**

Start both. Cancel the feed handle. Feed outcome is `.cancelled`. Profile handle still completes and writes profile state.

---

## Scorecard

| # | Name | Cold-start pass? |
|---|---|---|
| 1 | Sync scaffold | |
| 2 | Search replaces the previous load | |
| 3 | `finish()` in `.task` / `.refreshable` | |
| 4 | Events, not alert flags | |
| 5 | Injected tests, no UI | |
| 6 | Shared owner + full cancel | |
| 7 | `dropWhileRunning` vs `reduce` | |
| 8 | Slider stays `@State` | |
| 9 | Callback Work lifetime | |
| 10 | `handle.cancel()` isolation | |

Brick threshold: **10/10**. Below that, fix the skill text for the failed scenario before adding API.
