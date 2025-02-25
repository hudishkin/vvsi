//
//  ListView+Interactor.swift
//  VVSIExample
//
//  Created by Simon Hudishkin on 16.02.2025.
//

import VVSI

extension ListView {

    final class Interactor: ViewStateInteractor<VState, VAction, VNotification> {

        override init() {
            super.init()
        }

        override func execute(
            _ action: VAction,
            _ updater: @escaping StateUpdater<VState>
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


