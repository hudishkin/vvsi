//
//  ListView+Interactor.swift
//  VVSIExample
//
//  Created by Simon Hudishkin on 16.02.2025.
//

import VVSI

extension RemoteView {

    final class Interactor: ViewStateInteractor<VState, VAction, VNotification> {

        override init() {
            super.init()
        }

        override func execute(
            _ action: VAction,
            _ updater: @escaping StateUpdater<VState>
        ) {
            switch action {
            case .load:
                Task {
                    do {
                        notifications.send(.event("Starting"))
                        let products = try await self.fetchData()
                        await MainActor.run {
                            updater { state in
                                state.items = products.map { .init(
                                    id: $0.id,
                                    title: $0.title,
                                    image: $0.image)
                                }
                            }
                            notifications.send(.event("Finished"))
                        }
                    } catch {
                        notifications.send(.event("Finished with error"))
                        await MainActor.run {
                            updater { state in
                                state.items = []
                            }
                        }
                    }

                }
            }
        }
    }

}


