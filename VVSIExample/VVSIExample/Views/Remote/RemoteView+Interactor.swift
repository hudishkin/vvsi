import VVSI

extension RemoteView {
    final class Interactor: ViewStateInteractorProtocol {
        typealias S = VState
        typealias A = VAction
        typealias N = VEvent
        typealias FetchProducts = @Sendable () async throws -> [ProductDTO]

        let events = EventPipe<N>()
        private let fetchProducts: FetchProducts

        init(fetchProducts: @escaping FetchProducts = { try await Interactor.fetchData() }) {
            self.fetchProducts = fetchProducts
        }

        @MainActor
        func reduce(_ state: inout S, _ action: A) -> Work<S>? {
            switch action {
            case .load, .refresh:
                return Work { [fetchProducts, events] _, updater in
                    do {
                        try Task.checkCancellation()
                        let products = try await fetchProducts()
                        try Task.checkCancellation()
                        await updater { state in
                            state.items = products.map {
                                .init(id: $0.id, title: $0.title, image: $0.image)
                            }
                        }
                    } catch {
                        // URLSession can report URLError.cancelled instead of CancellationError.
                        guard !Task.isCancelled else { return }
                        events.send(.event("Could not load products. Pull to retry."))
                    }
                }
            }
        }
    }
}
