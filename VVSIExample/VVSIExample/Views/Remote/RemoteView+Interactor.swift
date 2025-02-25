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

        init() {

        }

        func execute(
            _ state: CurrentState<VState>,
            _ action: VAction,
            _ updater: @escaping StateUpdater<VState>
        ) {
            switch action {
            case .load:
                Task.detached { [self] in
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


