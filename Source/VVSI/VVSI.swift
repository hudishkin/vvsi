import Combine
import Dispatch

/// MainActor-owned feature state with Combine/ObservableObject observation.
@MainActor
public final class ViewState<Interactor: ViewStateInteractorProtocol>: ViewStateProtocol {
    public let events: AnyPublisher<Interactor.N, Never>

    @Published
    public private(set) var state: Interactor.S {
        didSet { runner.record(state) }
    }

    /// True while a non-concurrent Work occupies the slot.
    @Published
    public private(set) var isWorking = false

    private let interactor: Interactor
    private let runner: WorkRunner<Interactor.S>

    var activeWorkCount: Int { runner.activeWorkCount }

    public init(_ state: Interactor.S, _ interactor: Interactor) {
        self.state = state
        self.interactor = interactor
        self.runner = WorkRunner(state)
        self.events = interactor.events.publisher
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
        runner.onSlotChange = { [weak self] busy in
            guard let self, self.isWorking != busy else { return }
            self.isWorking = busy
        }
    }

    public convenience init(_ interactor: Interactor) where Interactor: InitialStateProtocol {
        self.init(interactor.initialState, interactor)
    }

    /// Applies the reduction before returning. Synchronous actions create no task.
    @discardableResult
    public func trigger(_ action: Interactor.A) -> WorkHandle? {
        guard let work = interactor.reduce(&state, action) else { return nil }
        return runner.start(work) { [weak self] update in
            guard let self else { return }
            update(&self.state)
        }
    }

    /// Invalidates all work, then asks the Interactor to clear leftover flags.
    public func cancel() {
        runner.cancel()
        interactor.didCancel(&state)
    }

    public func eventStream(
        bufferingPolicy: AsyncStream<Interactor.N>.Continuation.BufferingPolicy = .bufferingNewest(1)
    ) -> AsyncStream<Interactor.N> {
        interactor.events.stream(bufferingPolicy: bufferingPolicy)
    }
}
