import Combine
import Dispatch

#if canImport(Observation)
import Observation

/// Observation adapter using the same Work runtime as ViewState.
@available(iOS 17, macOS 14, tvOS 17, *)
@MainActor
@Observable
public final class ObservableViewState<Interactor: ViewStateInteractorProtocol> {
    public let events: AnyPublisher<Interactor.N, Never>

    public private(set) var state: Interactor.S {
        didSet { runner.record(state) }
    }

    /// True while a non-concurrent Work occupies the slot.
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

    @discardableResult
    public func trigger(_ action: Interactor.A) -> WorkHandle? {
        guard let work = interactor.reduce(&state, action) else { return nil }
        return runner.start(work) { [weak self] update in
            guard let self else { return }
            update(&self.state)
        }
    }

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
#endif
