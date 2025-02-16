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
        
        override func execute(_ action: VAction, _ updater: @escaping (@escaping (inout S) -> Void) -> Void) {

            switch action {
            case .add:
                updater { state in
                    state.items.append("New item")
                }
            case .remove:
                updater { state in
                    if !state.items.isEmpty {
                        state.items.removeLast()
                    }
                }
            }

        }
    }

}


