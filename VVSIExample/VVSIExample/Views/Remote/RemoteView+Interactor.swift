//
//  ListView+Interactor.swift
//  VVSIExample
//
//  Created by Simon Hudishkin on 16.02.2025.
//

import VVSI
@preconcurrency import Combine

extension RemoteView {

    final class Interactor: ViewStateInteractorProtocol {

        typealias S = VState
        typealias A = VAction
        typealias N = VNotification

        let notifications: PassthroughSubject<N, Never> = .init()

        init() { }

        func execute(
            _ state: @escaping CurrentState<S>,
            _ action: A,
            _ updater: @escaping StateUpdater<S>
        ) {
            switch action {
            case .refresh(let action):
                Task { [weak self] in
                    guard let self else { return }

                    await updater { state in
                        state.items = []
                    }

                    try? await Task.sleep(for: .seconds(1))

                    let products = try await self.fetchData()
                    await updater { state in
                        state.items = products.map { .init(
                            id: $0.id,
                            title: $0.title,
                            image: $0.image)
                        }
                    }

                    action()
                }

            case .load:
                Task.detached { [weak self] in
                    guard let self else { return }

                    do {
                        notifications.send(.event("Starting"))
                        let products = try await self.fetchData()
                        await updater { state in
                            state.items = products.map { .init(
                                id: $0.id,
                                title: $0.title,
                                image: $0.image)
                            }
                        }

                        notifications.send(.event("Finished"))

                    } catch {
                        notifications.send(.event("Finished with error"))

                        await updater { state in
                            state.items = []
                        }
                    }

                }
            }
        }
    }

}


