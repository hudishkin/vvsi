import VVSI

extension RemoteView {

    final class Interactor: ViewStateInteractorProtocol, @unchecked Sendable {

        typealias S = VState
        typealias A = VAction
        typealias N = VEvent

        let events = EventPipe<N>()

        init() {}

        @MainActor
        func reduce(_ state: inout S, _ action: A) -> Work<S>? {
            switch action {
            case .refresh(let completion):
                state.items = []

                return Work(policy: .cancelPrevious("products")) { [self] _, updater in
                    defer { completion() }

                    do {
                        try await Task.sleep(for: .seconds(1))
                        let products = try await fetchData()
                        try Task.checkCancellation()
                        await updater { state in
                            state.items = products.map {
                                .init(id: $0.id, title: $0.title, image: $0.image)
                            }
                        }
                    } catch is CancellationError {
                        return
                    } catch {
                        events.send(.event("Refresh failed"))
                    }
                }

            case .load:
                return Work(policy: .cancelPrevious("products")) { [self] _, updater in
                    events.send(.event("Starting"))

                    do {
                        let products = try await fetchData()
                        try Task.checkCancellation()
                        await updater { state in
                            state.items = products.map {
                                .init(id: $0.id, title: $0.title, image: $0.image)
                            }
                        }
                        events.send(.event("Finished"))
                    } catch is CancellationError {
                        return
                    } catch {
                        events.send(.event("Finished with error"))
                        await updater { state in
                            state.items = []
                        }
                    }
                }
            }
        }
    }
}
