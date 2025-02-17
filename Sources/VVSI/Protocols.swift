import Combine

public protocol StateProtocol { }
public protocol ActionProtocol { }
public protocol NotificationProtocol { }

extension Never: StateProtocol { }
extension Never: ActionProtocol { }
extension Never: NotificationProtocol { }

public typealias StateUpdater<S> = ((@escaping (inout S) -> Void) -> Void)

public protocol ViewStateProtocol: ObservableObject where ObjectWillChangePublisher.Output == Void {

    associatedtype S = StateProtocol
    associatedtype A = ActionProtocol
    associatedtype N = NotificationProtocol

    var notifications: AnyPublisher<N, Never> { get }
    var state: S { get }

    func trigger(_ action: A)
}


public protocol ViewStateInteractorProtocol {

    associatedtype S = StateProtocol
    associatedtype A = ActionProtocol
    associatedtype N = NotificationProtocol

    var notifications: PassthroughSubject<N, Never> { get }

    func execute(
        _ action: A,
        _ updater: @escaping StateUpdater<S>
    )
}
