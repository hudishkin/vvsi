# View - ViewState - Interactor

Experimental architecture for SwiftUI application. Something between TCA and MVVM.

## Usage

Here's a basic example of how to use:

```swift

// ListView.swift

import VVSI
import SwiftUI

struct ListView: View {

    @StateObject
    var viewState = ViewState(.init(items: []), Interactor())

    var body: some View {

        ForEach(viewState.state.items, id: \.self) { item in
            Text(item)
        }

        HStack {
            Button {
                viewState.trigger(.add)
            } label: {
                Text("Add")
            }

            Button {
                viewState.trigger(.remove)
            } label: {
                Text("Remove")
            }
        }
    }

}

```

```swift

// ListView+State.swift

extension ListView {

    struct VState: StateProtocol {
        var items: [String]
    }

    enum VAction: ActionProtocol {
        case add
        case remove
    }

    enum VNotification: NotificationProtocol { }

}

```

```swift

// ListView+Interactor.swift

extension ListView {

    final class Interactor: ViewStateInteractor {
        
        typealias S = VState
        typealias A = VAction
        typealias N = VNotification

        init() { }
        
        override func execute(
            _ action: A,
            _ updater: @escaping StateUpdater<S>
        ) {
            switch action {
            case .add:
                Task {
                    await updater { state in
                        state.items.append("New item")
                    }
                }
            case .remove:
                Task {
                    await updater { state in
                        if !state.items.isEmpty {
                            state.items.removeLast()
                        }
                    }
                
                }
            }
        }
    }

}

```

For more see [example](/VVSIExample).
