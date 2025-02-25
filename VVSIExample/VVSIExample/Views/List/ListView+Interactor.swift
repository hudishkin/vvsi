//
//  ListView+Interactor.swift
//  VVSIExample
//
//  Created by Simon Hudishkin on 16.02.2025.
//

import VVSI
@preconcurrency import Combine

extension ListView {

    final class Interactor: ViewStateInteractorProtocol {

        typealias S = VState
        typealias A = VAction
        typealias N = VNotification

        let notifications: PassthroughSubject<N, Never> = .init()

        init() { }

        func execute(
            _ state: CurrentState<VState>,
            _ action: VAction,
            _ updater: @escaping StateUpdater<VState>
        ) {
            switch action {
            case .add:
                Task.detached {
                    await updater { state in
                        state.items.append("New item")
                    }
                }

            case .remove:
                Task.detached {
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


