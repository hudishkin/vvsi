# VVSI templates (unreleased after 0.2.0-alpha.1)

Replace `FeatureName` with the screen name (e.g. `Profile`, `List`).

## FeatureName+State.swift

```swift
import VVSI

extension FeatureName {

    struct VState: StateProtocol {
        var title: String = ""
    }

    enum VAction: ActionProtocol {
        case onAppear
        case reload
    }

    enum VEvent: EventProtocol {
        case error(String)
    }
}
```

No `isLoading` field: the View reads `viewState.isWorking`.

## FeatureName+Interactor.swift

```swift
import VVSI

extension FeatureName {

    final class Interactor: ViewStateInteractorProtocol {

        typealias S = VState
        typealias A = VAction
        typealias N = VEvent

        let events = EventPipe<N>()

        init() {}

        @MainActor
        func reduce(_ state: inout S, _ action: A) -> Work<S>? {
            switch action {
            case .onAppear, .reload:
                return Work { [events] _, updater in
                    do {
                        // let data = try await fetch...
                        try Task.checkCancellation()
                        await updater { state in
                            state.title = "Loaded"
                        }
                    } catch {
                        guard !Task.isCancelled else { return }
                        events.send(.error(error.localizedDescription))
                    }
                }
            }
        }
    }
}
```

### With InitialStateProtocol

```swift
final class Interactor: ViewStateInteractorProtocol, InitialStateProtocol {
    typealias S = VState
    typealias A = VAction
    typealias N = VEvent

    let events = EventPipe<N>()
    let initialState = VState(title: "Hello")

    // reduce(...) as above
}
```

## FeatureName.swift

```swift
import SwiftUI
import VVSI

@MainActor
struct FeatureName: View {

    enum AlertType: Identifiable {
        var id: String { "\(self)" }
        case error(String)
    }

    // iOS 17+ / macOS 14+ / tvOS 17+.
    @State
    private var viewState = ObservableViewState(.init(), Interactor())
    // or: ObservableViewState(Interactor()) when using InitialStateProtocol
    // Older targets: @StateObject private var viewState = ViewState(.init(), Interactor())

    @State
    private var alertType: AlertType?

    var body: some View {
        VStack {
            if viewState.isWorking {
                ProgressView()
            }
            Text(viewState.state.title)
            Button("Reload") {
                viewState.trigger(.reload)
            }
        }
        .task {
            await viewState.trigger(.onAppear)?.finish()
        }
        .alert(item: $alertType) { item in
            switch item {
            case .error(let message):
                Alert(
                    title: Text("Error"),
                    message: Text(message),
                    dismissButton: .default(Text("Ok"))
                )
            }
        }
        .onReceive(viewState.events) { event in
            switch event {
            case .error(let message):
                alertType = .error(message)
            }
        }
    }
}
```

`@State` evaluates the `ObservableViewState(...)` initializer whenever the parent rebuilds the view and keeps only the first instance. Keep `Interactor.init` cheap: store dependencies, start requests from `.task`.

For async event consumption instead of `.onReceive`, request a stream when the consumer starts:

```swift
for await event in viewState.eventStream() {
    // Handle event.
}
```

Each call creates an independent subscription and keeps only the newest pending event by default.

Synchronous actions should mutate `state` and return `nil`. A plain `Work` replaces the previous one. Use `Work(.dropWhileRunning)` to ignore a duplicate of that same slot, and `Work(.concurrent)` only when the operation must keep running beside it. Stop one concurrent operation with the handle `trigger` returned. Split large feature state into focused screens, and keep high-frequency intermediate UI values in local `@State`.

The View template uses iOS/tvOS 17+ and macOS 14+ APIs. The library itself supports older deployment targets through `ViewState`. A dropped Work still performs its synchronous reduction. `finish()` returns promptly on cancellation even if the underlying operation ignores cancellation.
