import SwiftUI
import Combine

public final class ViewState<Interactor: ViewStateInteractorProtocol>: @preconcurrency ViewStateProtocol where Interactor.S: StateProtocol, Interactor.A: ActionProtocol, Interactor.N: NotificationProtocol {

    private(set) public var notifications: AnyPublisher<Interactor.N, Never>

    @Published
    private(set) public var state: Interactor.S

    private var interactor: Interactor

    public init(
        _ state: Interactor.S,
        _ interactor: Interactor
    ) {
        self.state = state
        self.interactor = interactor
        self.notifications = interactor.notifications.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    public func trigger(_ action: Interactor.A) {
        interactor.execute({ state }, action) { [weak self] updater in
            guard let self else { return }

            await updater(&state)
        }
    }

}
