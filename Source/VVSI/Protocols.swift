import Combine

public protocol StateProtocol: Sendable { }
public protocol ActionProtocol { }
public protocol EventProtocol: Sendable { }

extension Never: StateProtocol { }
extension Never: ActionProtocol { }
extension Never: EventProtocol { }

/// Reads the current feature state on the main actor. After the owner is released,
/// returns its last committed state without retaining the owner.
public typealias CurrentState<S> = @MainActor @Sendable () -> S

/// Applies a synchronous state mutation on the main actor while the originating
/// Work is active. Calls after cancellation or completion are ignored, including
/// calls made by another task or an escaped callback.
public typealias StateUpdater<S> = @MainActor @Sendable (
    @escaping @Sendable (inout S) -> Void
) -> Void

/// How a new Work interacts with work that is already running.
///
/// A screen has one slot. The default, `.cancelPrevious`, replaces whatever is
/// in that slot, so load and refresh cannot miss each other and there is no
/// name to mistype. `.dropWhileRunning` uses the same slot but does not start
/// while it is busy. `.concurrent` stays outside the slot: a later `Work`
/// neither waits for it nor cancels it. Cancel that work through the handle
/// `trigger` returned, or cancel everything with `cancel()`.
public enum WorkPolicy: Sendable, Equatable {
    case cancelPrevious
    case dropWhileRunning
    case concurrent
}

public struct Work<S: StateProtocol>: Sendable {
    public typealias Operation = @Sendable (
        _ state: @escaping CurrentState<S>,
        _ updater: @escaping StateUpdater<S>
    ) async -> Void

    public let policy: WorkPolicy
    let operation: Operation

    /// A plain `Work { }` replaces the work already in the slot.
    public init(
        _ policy: WorkPolicy = .cancelPrevious,
        operation: @escaping Operation
    ) {
        self.policy = policy
        self.operation = operation
    }
}

@MainActor
public protocol ViewStateProtocol: AnyObject, ObservableObject where ObjectWillChangePublisher.Output == Void {

    associatedtype S: StateProtocol
    associatedtype A: ActionProtocol
    associatedtype N: EventProtocol

    var events: AnyPublisher<N, Never> { get }
    var state: S { get }

    /// True from `trigger` until the slot's Work completes or is cancelled,
    /// including while one Work replaces another. `.concurrent` work is excluded.
    var isWorking: Bool { get }

    /// Reduces synchronously, returning a handle only when Work is produced.
    @discardableResult
    func trigger(_ action: A) -> WorkHandle?

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

    /// Called only from `viewState.cancel()` after work is invalidated.
    /// Default is a no-op. Loading indicators belong to `isWorking`; use this
    /// only for other state that a full cancel must reset.
    /// Not invoked by `handle.cancel()`, a replaced `Work`, `.dropWhileRunning`, or `finish()`.
    @MainActor
    func didCancel(_ state: inout S)
}

public extension ViewStateInteractorProtocol {
    func didCancel(_ state: inout S) {}
}

public protocol InitialStateProtocol: ViewStateInteractorProtocol {
    @MainActor
    var initialState: S { get }
}
