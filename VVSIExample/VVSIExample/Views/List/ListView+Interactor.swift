//
//  ListView+Interactor.swift
//  VVSIExample
//
//  Created by Simon Hudishkin on 16.02.2025.
//

import VVSI
@preconcurrency import Combine

class Dependencies {

    class Service { }

    var service: Service

    init(service: Service) {
        self.service = service
    }

}

extension ListView {

    final class Interactor: ViewStateInteractorProtocol {

        typealias S = VState
        typealias A = VAction
        typealias N = VNotification

        let notifications: PassthroughSubject<N, Never> = .init()
        let service: Dependencies.Service

        init(dependencies: Dependencies) {
            service = dependencies.service
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
                    await updater { state in
                        state.items.append("New item")
                    }

                    if await state().items.count < 5 {
                        await self?.execute(state, action, updater)
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
