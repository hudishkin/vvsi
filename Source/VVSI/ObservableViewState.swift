import SwiftUI
import Combine

#if canImport(Observation)
import Observation

/// Experimental Observation-based mirror of `ViewState`.
/// Prefer classic `ViewState` for production until this API stabilizes.
@available(iOS 17, macOS 14, tvOS 17, *)
@Observable
public final class ObservableViewState<Interactor: ViewStateInteractorProtocol>
where Interactor.S: StateProtocol, Interactor.A: ActionProtocol, Interactor.N: EventProtocol {

    @ObservationIgnored
    private(set) public var events: AnyPublisher<Interactor.N, Never>

    public private(set) var state: Interactor.S

    @ObservationIgnored
    private let interactor: Interactor

    private struct RunningWork {
        let key: String?
        let task: Task<Void, Never>
    }

    @ObservationIgnored
    private var nextWorkID: UInt64 = 0

    @ObservationIgnored
    private var runningWork: [UInt64: RunningWork] = [:]

    @MainActor
    var activeWorkCount: Int {
        runningWork.count
    }

    public init(
        _ state: Interactor.S,
        _ interactor: Interactor
    ) {
        self.state = state
        self.interactor = interactor
        self.events = interactor.events.publisher
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    public init(
        _ interactor: Interactor
    ) where Interactor: InitialStateProtocol {
        self.state = interactor.initialState
        self.interactor = interactor
        self.events = interactor.events.publisher
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    @MainActor
    public func trigger(_ action: Interactor.A) {
        guard let work = interactor.reduce(&state, action) else {
            return
        }
        start(work)
    }

    @MainActor
    private func start(_ work: Work<Interactor.S>) {
        let key = work.policy.key

        switch work.policy {
        case .concurrent:
            break
        case .cancelPrevious:
            let matchingIDs = runningWork.compactMap { id, running in
                running.key == key ? id : nil
            }
            for id in matchingIDs {
                runningWork[id]?.task.cancel()
                runningWork[id] = nil
            }
        case .dropWhileRunning:
            guard !runningWork.values.contains(where: { $0.key == key }) else {
                return
            }
        }

        let id = nextWorkID
        nextWorkID &+= 1

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.runningWork[id] = nil }
            guard !Task.isCancelled else { return }

            await work.operation(
                { self.state },
                { [weak self] update in
                    guard let self, !Task.isCancelled else { return }
                    update(&self.state)
                }
            )
        }
        runningWork[id] = RunningWork(key: key, task: task)
    }

    /// Cancels all in-flight work (e.g. on disappear).
    @MainActor
    public func cancel() {
        for running in runningWork.values {
            running.task.cancel()
        }
        runningWork.removeAll()
    }

    public func eventStream(
        bufferingPolicy: AsyncStream<Interactor.N>.Continuation.BufferingPolicy = .bufferingNewest(1)
    ) -> AsyncStream<Interactor.N> {
        interactor.events.stream(bufferingPolicy: bufferingPolicy)
    }
}
#endif
