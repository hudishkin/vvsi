import Combine

public protocol StateProtocol: Sendable { }
public protocol ActionProtocol { }
public protocol EventProtocol: Sendable { }

extension Never: StateProtocol { }
extension Never: ActionProtocol { }
extension Never: EventProtocol { }

/// Reads the current feature state on the main actor.
public typealias CurrentState<S> = @MainActor @Sendable () -> S

/// Applies a synchronous state mutation on the main actor.
public typealias StateUpdater<S> = @MainActor @Sendable (
    @escaping @Sendable (inout S) -> Void
) -> Void

public enum WorkPolicy: Sendable, Equatable {
    case concurrent
    case cancelPrevious(String)
    case dropWhileRunning(String)

    var key: String? {
        switch self {
        case .concurrent:
            nil
        case .cancelPrevious(let key), .dropWhileRunning(let key):
            key
        }
    }
}

public struct Work<S: StateProtocol>: Sendable {
    public typealias Operation = @Sendable (
        _ state: @escaping CurrentState<S>,
        _ updater: @escaping StateUpdater<S>
    ) async -> Void

    public let policy: WorkPolicy
    let operation: Operation

    public init(
        policy: WorkPolicy = .concurrent,
        operation: @escaping Operation
    ) {
        self.policy = policy
        self.operation = operation
    }
}

public protocol ViewStateProtocol: AnyObject, ObservableObject where ObjectWillChangePublisher.Output == Void {

    associatedtype S: StateProtocol
    associatedtype A: ActionProtocol
    associatedtype N: EventProtocol

    var events: AnyPublisher<N, Never> { get }
    var state: S { get }

    @MainActor
    func trigger(_ action: A)

    @MainActor
    func cancel()

    func eventStream(
        bufferingPolicy: AsyncStream<N>.Continuation.BufferingPolicy
    ) -> AsyncStream<N>
}

public extension ViewStateProtocol {
    func eventStream() -> AsyncStream<N> {
        eventStream(bufferingPolicy: .bufferingNewest(1))
    }
}

public protocol ViewStateInteractorProtocol: AnyObject {

    associatedtype S: StateProtocol
    associatedtype A: ActionProtocol
    associatedtype N: EventProtocol

    var events: EventPipe<N> { get }

    @MainActor
    func reduce(_ state: inout S, _ action: A) -> Work<S>?
}

public protocol InitialStateProtocol: ViewStateInteractorProtocol {
    var initialState: S { get }
}
