import SwiftUI
import Combine

public final class ViewState<State: StateProtocol, Action: ActionProtocol, Notification: NotificationProtocol>: ViewStateProtocol {

    private(set) public var notifications: AnyPublisher<Notification, Never>
    @Published
    private(set) public var state: State

    private var interactor: ViewStateInteractor<State, Action, Notification>

    public init(
        _ state: State,
        _ interactor: ViewStateInteractor<State, Action, Notification>
    ) {
        self.state = state
        self.interactor = interactor
        self.notifications = interactor.notifications.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    public func trigger(_ action: Action) {
        interactor.execute(action) { [weak self] updater in
            guard let self else { return }

            assert(Thread.isMainThread)

            var state = self.state
            updater(&state)
            self.state = state
        }
    }

}

open class ViewStateInteractor<State: StateProtocol, Action: ActionProtocol, Notification: NotificationProtocol>: ViewStateInteractorProtocol {

    public var notifications: PassthroughSubject<Notification, Never> = .init()

    public init() {}

    open func execute(
        _ action: Action,
        _ update: @escaping StateUpdater<State>
    ) { }
}
