import Combine
import Testing
@testable import VVSI

private struct TestState: StateProtocol {
    var items: [String]
}

private enum TestAction: ActionProtocol {
    case add
    case remove
    case blockingWork
}

private enum TestEvent: EventProtocol, Equatable {
    case error(String)
    case finished
}

private actor WorkProbe {
    private(set) var starts = 0
    private(set) var completions = 0

    func started() {
        starts += 1
    }

    func completed() {
        completions += 1
    }
}

private final class TestInteractor: ViewStateInteractorProtocol {
    typealias S = TestState
    typealias A = TestAction
    typealias N = TestEvent

    let events = EventPipe<N>()
    let maxItems: Int
    let probe = WorkProbe()

    init(maxItems: Int = 5) {
        self.maxItems = maxItems
    }

    @MainActor
    func reduce(_ state: inout S, _ action: A) -> Work<S>? {
        switch action {
        case .add:
            guard state.items.count < maxItems else {
                events.send(.error("Max items count is \(maxItems)"))
                return nil
            }
            state.items.append("New item")
            return nil

        case .remove:
            if !state.items.isEmpty {
                state.items.removeLast()
            }
            return nil

        case .blockingWork:
            return Work { [probe] _, _ in
                await probe.started()
                let clock = ContinuousClock()
                let deadline = clock.now.advanced(by: .milliseconds(150))
                while clock.now < deadline {}
                await probe.completed()
            }
        }
    }
}

@Suite("ViewState", .timeLimit(.minutes(1)))
@MainActor
struct ViewStateTests {

    @Test("trigger(.add) updates state")
    func addsItemSynchronouslyWithoutWork() {
        let viewState = ViewState(TestState(items: []), TestInteractor())
        viewState.trigger(.add)

        #expect(viewState.state.items == ["New item"])
        #expect(viewState.activeWorkCount == 0)
    }

    @Test("trigger(.remove) updates state")
    func removesItemSynchronouslyWithoutWork() {
        let viewState = ViewState(TestState(items: ["a", "b"]), TestInteractor())
        viewState.trigger(.remove)

        #expect(viewState.state.items == ["a"])
        #expect(viewState.activeWorkCount == 0)
    }

    @Test("limit reached sends event and does not mutate state")
    func limitSendsEvent() async {
        let viewState = ViewState(
            TestState(items: ["1", "2", "3"]),
            TestInteractor(maxItems: 3)
        )

        let (stream, continuation) = AsyncStream<TestEvent>.makeStream()
        let cancellable = viewState.events.sink { continuation.yield($0) }
        defer { cancellable.cancel() }
        var iterator = stream.makeAsyncIterator()

        viewState.trigger(.add)
        #expect(await iterator.next() == .error("Max items count is 3"))
        #expect(viewState.state.items == ["1", "2", "3"])
        _ = cancellable
    }

    @Test("eventStream yields events")
    func eventStreamYields() async {
        let interactor = TestInteractor(maxItems: 0)
        let viewState = ViewState(TestState(items: []), interactor)
        let stream = viewState.eventStream()

        var iterator = stream.makeAsyncIterator()
        viewState.trigger(.add)
        #expect(await iterator.next() == .error("Max items count is 0"))
    }

    @Test("eventStream subscribes lazily")
    func eventStreamSubscribesLazily() async {
        let interactor = TestInteractor(maxItems: 0)
        let viewState = ViewState(TestState(items: []), interactor)

        interactor.events.send(.error("before subscription"))
        var iterator = viewState.eventStream().makeAsyncIterator()
        interactor.events.send(.finished)

        #expect(await iterator.next() == .finished)
    }

    @Test("eventStream keeps only the newest buffered event by default")
    func eventStreamUsesBoundedBuffer() async {
        let pipe = EventPipe<TestEvent>()
        var iterator = pipe.stream().makeAsyncIterator()

        pipe.send(.error("old"))
        pipe.send(.finished)

        #expect(await iterator.next() == .finished)
    }

    @Test("separate event streams each receive the event")
    func eventStreamsAreIndependent() async {
        let pipe = EventPipe<TestEvent>()
        var first = pipe.stream().makeAsyncIterator()
        var second = pipe.stream().makeAsyncIterator()

        pipe.send(.finished)

        #expect(await first.next() == .finished)
        #expect(await second.next() == .finished)
    }

    @Test("eventStream supports bufferingOldest")
    func eventStreamSupportsCustomBuffering() async {
        let pipe = EventPipe<TestEvent>()
        var iterator = pipe.stream(
            bufferingPolicy: .bufferingOldest(1)
        ).makeAsyncIterator()

        pipe.send(.error("old"))
        pipe.send(.finished)

        #expect(await iterator.next() == .error("old"))
    }

    @Test("publisher and eventStream both receive an event")
    func publisherAndStreamReceiveSameEvent() async {
        let pipe = EventPipe<TestEvent>()
        var published: TestEvent?
        let cancellable = pipe.publisher.sink { published = $0 }
        var iterator = pipe.stream().makeAsyncIterator()

        pipe.send(.finished)

        #expect(published == .finished)
        #expect(await iterator.next() == .finished)
        _ = cancellable
    }

    @Test("Work body does not block MainActor")
    func workRunsOutsideMainActor() async {
        let interactor = TestInteractor()
        let viewState = ViewState(TestState(items: []), interactor)

        viewState.trigger(.blockingWork)
        await waitForAsync { await interactor.probe.starts == 1 }

        #expect(await interactor.probe.completions == 0)
        viewState.trigger(.add)
        #expect(viewState.state.items == ["New item"])

        await waitForAsync { await interactor.probe.completions == 1 }
    }

    @Test("InitialStateProtocol seeds ViewState")
    func initialStateProtocol() {
        final class SeededInteractor: ViewStateInteractorProtocol, InitialStateProtocol {
            typealias S = TestState
            typealias A = TestAction
            typealias N = TestEvent

            let events = EventPipe<N>()
            let initialState = TestState(items: ["seed"])

            @MainActor
            func reduce(_ state: inout S, _ action: A) -> Work<S>? {
                nil
            }
        }

        let viewState = ViewState(SeededInteractor())
        #expect(viewState.state.items == ["seed"])
    }
}

#if canImport(Observation)
@Suite("ObservableViewState", .timeLimit(.minutes(1)))
@MainActor
struct ObservableViewStateTests {

    @Test("ObservableViewState updates state on supported OS")
    func updatesState() async throws {
        guard #available(iOS 17, macOS 14, tvOS 17, *) else {
            return
        }

        let viewState = ObservableViewState(TestState(items: []), TestInteractor())
        viewState.trigger(.add)

        #expect(viewState.state.items == ["New item"])
        #expect(viewState.activeWorkCount == 0)
    }

    @Test("ObservableViewState creates event streams on demand")
    func eventStreamIsLazy() async throws {
        guard #available(iOS 17, macOS 14, tvOS 17, *) else {
            return
        }

        let interactor = TestInteractor(maxItems: 0)
        let viewState = ObservableViewState(TestState(items: []), interactor)

        interactor.events.send(.error("before subscription"))
        var iterator = viewState.eventStream().makeAsyncIterator()
        interactor.events.send(.finished)

        #expect(await iterator.next() == .finished)
    }


}
#endif

@MainActor
private func waitForAsync(
    timeoutMs: Int = 1000,
    _ condition: @MainActor () async -> Bool
) async {
    let steps = max(timeoutMs / 10, 1)
    for _ in 0..<steps {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
    #expect(await condition(), "Condition not met within \(timeoutMs)ms")
}
