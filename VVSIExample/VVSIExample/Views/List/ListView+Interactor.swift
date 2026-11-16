import VVSI

extension ListView {

    final class Interactor: ViewStateInteractorProtocol, InitialStateProtocol {

        typealias S = VState
        typealias A = VAction
        typealias N = VEvent

        let events = EventPipe<N>()
        let initialState: VState

        init() {
            initialState = .init(items: [.init(title: "initial item")])
        }

        @MainActor
        func reduce(_ state: inout S, _ action: A) -> Work<S>? {
            switch action {
            case .add:
                guard state.items.count < 5 else {
                    events.send(.error("Max items count is 5"))
                    return nil
                }
                state.items.append(.init(title: "New item"))

            case .remove:
                if !state.items.isEmpty {
                    state.items.removeLast()
                }

            case .random(let options):
                state.items = (0..<options.count).map { _ in
                    .init(title: randomString(length: options.length))
                }
            }
            return nil
        }
    }
}

private func randomString(length: Int) -> String {
    let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    return String((0..<length).map { _ in letters.randomElement()! })
}
