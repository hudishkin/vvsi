import Combine

public protocol StateProtocol: Sendable { }
public protocol ActionProtocol { }
public protocol NotificationProtocol { }

extension Never: StateProtocol { }
extension Never: ActionProtocol { }
extension Never: NotificationProtocol { }

public typealias StateUpdater<S: Sendable> = ((@MainActor @escaping (inout S) -> Void) async -> Void)
public typealias CurrentState<S: Sendable> = @MainActor () async -> S

public protocol ViewStateProtocol: AnyObject, ObservableObject where ObjectWillChangePublisher.Output == Void {

    associatedtype S: StateProtocol
    associatedtype A: ActionProtocol
    associatedtype N: NotificationProtocol

    var notifications: AnyPublisher<N, Never> { get }
    var state: S { get }

    @MainActor
    func trigger(_ action: A)

}

public protocol ViewStateInteractorProtocol {

    associatedtype S: StateProtocol
    associatedtype A: ActionProtocol
    associatedtype N: NotificationProtocol

    var notifications: PassthroughSubject<N, Never> { get }

    @MainActor
    func execute(
        _ state: @escaping CurrentState<S>,
        _ action: A,
        _ updater: @escaping StateUpdater<S>
    )

}
