//
//  ListView+Interactor.swift
//  VVSIExample
//
//  Created by Simon Hudishkin on 16.02.2025.
//

import VVSI
@preconcurrency import Combine

extension ListView {

    final class Interactor: ViewStateInteractorProtocol, InitialStateProtocol {

        typealias S = VState
        typealias A = VAction
        typealias N = VNotification

        let notifications: PassthroughSubject<N, Never> = .init()
        let service: Dependencies.Service
        let initialState: ListView.VState

        init(dependencies: Dependencies = .shared) {
            service = dependencies.service
            initialState = .init(items: ["initial item"])
        }

        @MainActor
        func execute(
            _ state: @escaping CurrentState<S>,
            _ action: VAction,
            _ updater: @escaping StateUpdater<S>
        ) {
            switch action {
            case .add:
                Task.detached { [weak self] in
                    guard await state().items.count < 5 else {
                        self?.notifications.send(.error("Max items count is 5"))
                        return
                    }

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
            case .random(let opt):
                Task {
                    let strings = (0..<opt.count).map { _ in randomString(length: opt.length) }
                    await updater { state in
                        state.items = strings
                    }
                }
            }
        }
    }

}

func randomString(length: Int) -> String {
  let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  return String((0..<length).map{ _ in letters.randomElement()! })
}
