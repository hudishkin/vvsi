import SwiftUI
import Combine

public final class ViewState<Interactor: ViewStateInteractorProtocol>: ViewStateProtocol where Interactor.S: StateProtocol, Interactor.A: ActionProtocol, Interactor.N: NotificationProtocol {

    private(set) public var notifications: AnyPublisher<Interactor.N, Never>

    @Published
    private(set) public var state: Interactor.S

    private var interactor: Interactor
    
    @MainActor
    private lazy var currentState: CurrentState<Interactor.S> = {
        return self.state
    }

    public init(
        _ state: Interactor.S,
        _ interactor: Interactor
    ) {
        self.state = state
        self.interactor = interactor
        self.notifications = interactor.notifications.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    public init(
        _ interactor: Interactor
    ) where Interactor: InitialStateProtocol {
        self.state = interactor.initialState
        self.interactor = interactor
        self.notifications = interactor.notifications.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    @MainActor
    public func trigger(_ action: Interactor.A) {
        interactor.execute(
            currentState,
            action
        ) { [weak self] updater in
            guard let self else { return }

            await updater(&state)
        }
    }

}
