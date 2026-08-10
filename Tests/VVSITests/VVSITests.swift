import Combine
import Testing
@testable import VVSI

private struct TestState: StateProtocol {
    var items: [String]
}

private enum TestAction: ActionProtocol {
    case add
    case remove
    case slowAdd(WorkPolicy = .concurrent)
    case reduceThenSlowAdd(WorkPolicy)
    case updateAfterCancellation
    case blockingWork
}

private enum TestEvent: EventProtocol, Equatable {
    case error(String)
    case finished
}

private actor WorkProbe {
    private(set) var starts = 0
    private(set) var cancellations = 0
    private(set) var completions = 0

    func started() {
        starts += 1
    }

    func cancelled() {
        cancellations += 1
    }

    func completed() {
        completions += 1
    }
}

private final class TestInteractor: ViewStateInteractorProtocol, @unchecked Sendable {
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

        case .slowAdd(let policy):
            return Work(policy: policy) { [events, probe] _, updater in
                await probe.started()
                do {
                    try await Task.sleep(for: .milliseconds(100))
                    try Task.checkCancellation()
                    await updater { state in
                        state.items.append("Slow item")
                    }
                    events.send(.finished)
                    await probe.completed()
                } catch is CancellationError {
                    await probe.cancelled()
                } catch {
                    await probe.cancelled()
                }
            }

        case .reduceThenSlowAdd(let policy):
            state.items.append("Reduced")
            return Work(policy: policy) { [probe] _, updater in
                await probe.started()
                do {
                    try await Task.sleep(for: .milliseconds(100))
                    try Task.checkCancellation()
                    await updater { state in
                        state.items.append("Slow item")
                    }
                    await probe.completed()
                } catch is CancellationError {
                    await probe.cancelled()
                } catch {
                    await probe.cancelled()
                }
            }

        case .updateAfterCancellation:
            return Work { [probe] _, updater in
                await probe.started()
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch is CancellationError {
                    await updater { state in
                        state.items.append("Cancelled update")
                    }
                    await probe.cancelled()
                } catch {
                    await probe.cancelled()
                }
            }

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

@Suite("ViewState")
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

        var received: TestEvent?
        let cancellable = viewState.events.sink { received = $0 }

        viewState.trigger(.add)
        await waitFor { received != nil }

        #expect(received == .error("Max items count is 3"))
        #expect(viewState.state.items == ["1", "2", "3"])
        _ = cancellable
    }

    @Test("eventStream yields events")
    func eventStreamYields() async {
        let interactor = TestInteractor(maxItems: 0)
        let viewState = ViewState(TestState(items: []), interactor)
        let stream = viewState.eventStream()

        let streamTask = Task<TestEvent?, Never> {
            for await event in stream {
                return event
            }
            return nil
        }

        viewState.trigger(.add)

        let event = await streamTask.value
        #expect(event == .error("Max items count is 0"))
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

    @Test("concurrent policy runs every work item")
    func concurrentPolicyRunsAllWork() async {
        let interactor = TestInteractor()
        let viewState = ViewState(TestState(items: []), interactor)

        viewState.trigger(.slowAdd())
        viewState.trigger(.slowAdd())

        await waitForAsync { await interactor.probe.starts == 2 }
        await waitFor { viewState.state.items.count == 2 }

        #expect(await interactor.probe.completions == 2)
        #expect(viewState.activeWorkCount == 0)
    }

    @Test("cancelPrevious cancels matching work")
    func cancelPreviousPolicyReplacesWork() async {
        let interactor = TestInteractor()
        let viewState = ViewState(TestState(items: []), interactor)

        viewState.trigger(.slowAdd(.cancelPrevious("load")))
        await waitForAsync { await interactor.probe.starts == 1 }
        viewState.trigger(.slowAdd(.cancelPrevious("load")))

        await waitForAsync { await interactor.probe.starts == 2 }
        await waitForAsync { await interactor.probe.cancellations == 1 }
        await waitFor { viewState.state.items.count == 1 }
        await waitForAsync { await interactor.probe.completions == 1 }

        #expect(await interactor.probe.completions == 1)
    }

    @Test("dropWhileRunning ignores matching work")
    func dropWhileRunningPolicyDropsDuplicate() async {
        let interactor = TestInteractor()
        let viewState = ViewState(TestState(items: []), interactor)

        viewState.trigger(.slowAdd(.dropWhileRunning("load")))
        viewState.trigger(.slowAdd(.dropWhileRunning("load")))

        await waitForAsync { await interactor.probe.starts == 1 }
        await waitFor { viewState.state.items.count == 1 }

        #expect(await interactor.probe.starts == 1)
        #expect(await interactor.probe.completions == 1)
    }

    @Test("work policies isolate different keys")
    func workPoliciesIsolateKeys() async {
        let interactor = TestInteractor()
        let viewState = ViewState(TestState(items: []), interactor)

        viewState.trigger(.slowAdd(.cancelPrevious("A")))
        viewState.trigger(.slowAdd(.cancelPrevious("B")))
        await waitForAsync { await interactor.probe.starts == 2 }

        viewState.trigger(.slowAdd(.cancelPrevious("A")))

        await waitForAsync { await interactor.probe.starts == 3 }
        await waitForAsync { await interactor.probe.cancellations == 1 }
        await waitFor { viewState.state.items.count == 2 }
        await waitForAsync { await interactor.probe.completions == 2 }

        #expect(await interactor.probe.completions == 2)
    }

    @Test("dropWhileRunning drops Work but keeps synchronous reduction")
    func dropWhileRunningOnlyDropsWork() async {
        let interactor = TestInteractor()
        let viewState = ViewState(TestState(items: []), interactor)

        viewState.trigger(.reduceThenSlowAdd(.dropWhileRunning("load")))
        viewState.trigger(.reduceThenSlowAdd(.dropWhileRunning("load")))

        #expect(viewState.state.items == ["Reduced", "Reduced"])
        await waitFor { viewState.state.items.count == 3 }
        #expect(viewState.state.items == ["Reduced", "Reduced", "Slow item"])
        #expect(await interactor.probe.starts == 1)
    }

    @Test("cancel stops all in-flight work")
    func explicitCancelStopsAllWork() async {
        let interactor = TestInteractor()
        let viewState = ViewState(TestState(items: []), interactor)

        viewState.trigger(.slowAdd())
        viewState.trigger(.slowAdd())
        await waitForAsync { await interactor.probe.starts == 2 }
        viewState.cancel()

        await waitForAsync { await interactor.probe.cancellations == 2 }
        #expect(viewState.state.items.isEmpty)
        #expect(viewState.activeWorkCount == 0)
    }

    @Test("new work can start immediately after cancel")
    func workRestartsImmediatelyAfterCancel() async {
        let interactor = TestInteractor()
        let viewState = ViewState(TestState(items: []), interactor)

        viewState.trigger(.slowAdd(.dropWhileRunning("load")))
        await waitForAsync { await interactor.probe.starts == 1 }
        viewState.cancel()
        viewState.trigger(.slowAdd(.dropWhileRunning("load")))

        await waitForAsync { await interactor.probe.starts == 2 }
        await waitForAsync { await interactor.probe.cancellations == 1 }
        await waitFor { viewState.state.items == ["Slow item"] }
        await waitForAsync { await interactor.probe.completions == 1 }

        #expect(await interactor.probe.completions == 1)
    }

    @Test("cancelled work cannot update state")
    func cancelledWorkCannotUpdateState() async {
        let interactor = TestInteractor()
        let viewState = ViewState(TestState(items: []), interactor)

        viewState.trigger(.updateAfterCancellation)
        await waitForAsync { await interactor.probe.starts == 1 }
        viewState.cancel()
        await waitForAsync { await interactor.probe.cancellations == 1 }

        #expect(viewState.state.items.isEmpty)
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

    @Test("completed triggers do not block subsequent work")
    func completedTriggersAreRemoved() async {
        let viewState = ViewState(TestState(items: []), TestInteractor())

        viewState.trigger(.slowAdd(.dropWhileRunning("load")))
        await waitFor { viewState.state.items.count == 1 }
        await waitFor { viewState.activeWorkCount == 0 }
        viewState.trigger(.slowAdd(.dropWhileRunning("load")))
        await waitFor { viewState.state.items.count == 2 }

        #expect(viewState.state.items == ["Slow item", "Slow item"])
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
@Suite("ObservableViewState")
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

    @Test("ObservableViewState applies work policies")
    func appliesWorkPolicy() async throws {
        guard #available(iOS 17, macOS 14, tvOS 17, *) else {
            return
        }

        let interactor = TestInteractor()
        let viewState = ObservableViewState(TestState(items: []), interactor)

        viewState.trigger(.slowAdd(.dropWhileRunning("load")))
        viewState.trigger(.slowAdd(.dropWhileRunning("load")))

        await waitForAsync { await interactor.probe.starts == 1 }
        await waitFor { viewState.state.items == ["Slow item"] }
        await waitFor { viewState.activeWorkCount == 0 }
        #expect(viewState.activeWorkCount == 0)
    }
}
#endif

@MainActor
private func waitFor(
    timeoutMs: Int = 1000,
    _ condition: @MainActor () -> Bool
) async {
    let steps = max(timeoutMs / 10, 1)
    for _ in 0..<steps {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition(), "Condition not met within \(timeoutMs)ms")
}

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
