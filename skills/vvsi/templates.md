# VVSI templates (0.1+)

Replace `FeatureName` with the screen name (e.g. `Profile`, `List`).

## FeatureName+State.swift

```swift
import VVSI

extension FeatureName {

    struct VState: StateProtocol {
        var title: String = ""
        var isLoading: Bool = false
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
                state.isLoading = true

                return Work(policy: .cancelPrevious("load")) { [events] _, updater in
                    do {
                        // let data = try await fetch...
                        try Task.checkCancellation()
                        await updater { state in
                            state.title = "Loaded"
                            state.isLoading = false
                        }
                    } catch is CancellationError {
                        return
                    } catch {
                        await updater { state in
                            state.isLoading = false
                        }
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
    let initialState = VState(title: "Hello", isLoading: false)

    // reduce(...) as above
}
```

## FeatureName.swift

```swift
import SwiftUI
import VVSI

struct FeatureName: View {

    enum AlertType: Identifiable {
        var id: String { "\(self)" }
        case error(String)
    }

    @StateObject
    private var viewState = ViewState(.init(), Interactor())
    // or: ViewState(Interactor()) when using InitialStateProtocol

    @State
    private var alertType: AlertType?

    var body: some View {
        VStack {
            if viewState.state.isLoading {
                ProgressView()
            }
            Text(viewState.state.title)
            Button("Reload") {
                viewState.trigger(.reload)
            }
        }
        .onAppear {
            viewState.trigger(.onAppear)
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
        .onDisappear {
            viewState.cancel()
        }
    }
}
```

For async event consumption instead of `.onReceive`, request a stream when the consumer starts:

```swift
for await event in viewState.eventStream() {
    // Handle event.
}
```

Each call creates an independent subscription and keeps only the newest pending event by default.

Synchronous actions should mutate `state` and return `nil`. Use `.cancelPrevious(key)` for replaceable requests, `.dropWhileRunning(key)` for duplicate suppression, and `.concurrent` for independent work. Split large feature state into focused screens, and keep high-frequency intermediate UI values in local `@State`.
