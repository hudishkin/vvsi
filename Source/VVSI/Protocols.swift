import Combine

public protocol StateProtocol: Sendable { }
public protocol ActionProtocol: Sendable { }
public protocol NotificationProtocol: Sendable { }

extension Never: StateProtocol { }
extension Never: ActionProtocol { }
extension Never: NotificationProtocol { }

public typealias StateUpdater<S: Sendable> = ((@MainActor @escaping (inout S) -> Void) async -> Void)
public typealias CurrentState<S: Sendable> = () -> S

public protocol ViewStateProtocol: ObservableObject where ObjectWillChangePublisher.Output == Void {
    associatedtype S = StateProtocol
    associatedtype A = ActionProtocol
    associatedtype N = NotificationProtocol

    var notifications: AnyPublisher<N, Never> { get }
    var state: S { get }

    func trigger(_ action: A)
}


public protocol ViewStateInteractorProtocol: Sendable {
    associatedtype S = StateProtocol
    associatedtype A = ActionProtocol
    associatedtype N = NotificationProtocol

    var notifications: PassthroughSubject<N, Never> { get }

    func execute(
        _ state: CurrentState<S>,
        _ action: A,
        _ updater: @escaping StateUpdater<S>
    )
}
