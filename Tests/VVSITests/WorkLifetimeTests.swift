import Foundation
import Testing
#if canImport(Observation)
import Observation
#endif
@testable import VVSI

private struct FeatureState: StateProtocol {
    var value = 0
    var leftover = 0
}
private enum FeatureAction: ActionProtocol {
    case set(Int)
    case run(ControlledWork, WorkPolicy)
    case runDefault(ControlledWork)
    case reduceAndRun(ControlledWork, WorkPolicy)
}

// AsyncStream waits respond to test cancellation; no wall-clock polling is used.
private struct Signal: Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    init() { (stream, continuation) = AsyncStream.makeStream() }
    func open() { continuation.finish() }
    func wait() async { for await _ in stream {} }
}

// Intentionally ignores task cancellation to model a callback-based dependency.
// Each test opens the gate in defer, including after an assertion failure.
private final class ManualGate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if opened {
                lock.unlock()
                continuation.resume()
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }
    func open() {
        lock.lock()
        opened = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
    }
}

private actor ControlledWork {
    let started = Signal()
    let exited = Signal()
    let release = ManualGate()
    private var updater: StateUpdater<FeatureState>?
    private var reader: CurrentState<FeatureState>?
    private(set) var starts = 0
    private(set) var wasCancelled = false

    func run(_ reader: @escaping CurrentState<FeatureState>, _ updater: @escaping StateUpdater<FeatureState>) async {
        self.reader = reader
        self.updater = updater
        starts += 1
        started.open()
        await release.wait()
        wasCancelled = Task.isCancelled
        exited.open()
    }

    func write(_ value: Int) async { await updater? { $0.value = value } }
    func read() async -> Int? { await reader?().value }
}

private final class FeatureInteractor: ViewStateInteractorProtocol, InitialStateProtocol {
    typealias S = FeatureState
    typealias A = FeatureAction
    typealias N = Never
    let events = EventPipe<Never>()
    let initialState = FeatureState()

    @MainActor
    func reduce(_ state: inout S, _ action: A) -> Work<S>? {
        switch action {
        case .set(let value):
            state.value = value
            return nil
        case .reduceAndRun(let controlled, let policy):
            state.value += 1
            return Work(policy) { state, updater in
                await controlled.run(state, updater)
            }
        case .run(let controlled, let policy):
            return Work(policy) { state, updater in
                await controlled.run(state, updater)
            }
        case .runDefault(let controlled):
            return Work { state, updater in
                await controlled.run(state, updater)
            }
        }
    }

    @MainActor
    func didCancel(_ state: inout S) {
        state.leftover = -1
    }
}

@MainActor
private protocol FeatureStore: AnyObject {
    var state: FeatureState { get }
    var isWorking: Bool { get }
    var activeWorkCount: Int { get }
    @discardableResult func trigger(_ action: FeatureAction) -> WorkHandle?
    func cancel()
}

extension ViewState: FeatureStore where Interactor == FeatureInteractor {}
#if canImport(Observation)
@available(iOS 17, macOS 14, tvOS 17, *)
extension ObservableViewState: FeatureStore where Interactor == FeatureInteractor {}
#endif

private enum Adapter: Sendable {
    case classic, observation
    static var supported: [Self] {
        #if canImport(Observation)
        if #available(iOS 17, macOS 14, tvOS 17, *) { return [.classic, .observation] }
        #endif
        return [.classic]
    }

    @MainActor
    func make() -> any FeatureStore {
        switch self {
        case .classic: return ViewState(FeatureInteractor())
        case .observation:
            #if canImport(Observation)
            if #available(iOS 17, macOS 14, tvOS 17, *) { return ObservableViewState(FeatureInteractor()) }
            #endif
            preconditionFailure("Unsupported adapter")
        }
    }
}

@Suite("Work lifetime — both adapters", .timeLimit(.minutes(1)))
@MainActor
struct WorkLifetimeTests {
    @Test("Concurrent work all starts and cancel invalidates every callback", arguments: Adapter.supported)
    fileprivate func concurrentAndCancelAll(_ adapter: Adapter) async throws {
        let store = adapter.make()
        let first = ControlledWork(), second = ControlledWork()
        defer { first.release.open(); second.release.open() }
        let a = try #require(store.trigger(.run(first, .concurrent)))
        let b = try #require(store.trigger(.run(second, .concurrent)))
        await first.started.wait()
        await second.started.wait()
        #expect(store.activeWorkCount == 2)
        store.cancel()
        #expect(await a.finish() == .cancelled)
        #expect(await b.finish() == .cancelled)
        await first.write(1)
        await second.write(2)
        #expect(store.state.value == 0)
        #expect(store.activeWorkCount == 0)
    }

    @Test("Drop keeps the synchronous reduction", arguments: Adapter.supported)
    fileprivate func dropStillReduces(_ adapter: Adapter) async throws {
        let store = adapter.make()
        let first = ControlledWork(), second = ControlledWork()
        defer { first.release.open(); second.release.open() }
        let a = try #require(store.trigger(.reduceAndRun(first, .dropWhileRunning)))
        let b = try #require(store.trigger(.reduceAndRun(second, .dropWhileRunning)))
        #expect(store.state.value == 2)
        #expect(await b.finish() == .dropped)
        first.release.open()
        #expect(await a.finish() == .completed)
    }

    @Test("Replacement before start resolves the old handle", arguments: Adapter.supported)
    fileprivate func replacementBeforeStart(_ adapter: Adapter) async throws {
        let store = adapter.make()
        let first = ControlledWork(), second = ControlledWork()
        defer { first.release.open(); second.release.open() }
        let a = try #require(store.trigger(.run(first, .cancelPrevious)))
        let b = try #require(store.trigger(.run(second, .cancelPrevious)))
        #expect(await a.finish() == .cancelled)
        #expect(await first.starts == 0)
        second.release.open()
        #expect(await b.finish() == .completed)
    }

    @Test("Synchronous reduction has no work handle", arguments: Adapter.supported)
    fileprivate func synchronous(_ adapter: Adapter) {
        let store = adapter.make()
        #expect(store.state.value == 0)
        #expect(store.trigger(.set(3)) == nil)
        #expect(store.state.value == 3)
        #expect(store.activeWorkCount == 0)
    }

    @Test("CurrentState tracks synchronous and asynchronous mutations", arguments: Adapter.supported)
    fileprivate func currentState(_ adapter: Adapter) async throws {
        let store = adapter.make()
        let work = ControlledWork()
        defer { work.release.open() }
        let handle = try #require(store.trigger(.run(work, .concurrent)))
        await work.started.wait()
        store.trigger(.set(5))
        #expect(await work.read() == 5)
        await work.write(6)
        #expect(store.state.value == 6)
        #expect(await work.read() == 6)
        work.release.open()
        #expect(await handle.finish() == .completed)
        #expect(store.activeWorkCount == 0)
    }

    @Test("Owner is released even while work ignores cancellation", arguments: Adapter.supported)
    fileprivate func ownerLifetime(_ adapter: Adapter) async throws {
        var owner: (any FeatureStore)? = adapter.make()
        weak var reference = owner
        defer { reference = nil }
        let work = ControlledWork()
        defer { work.release.open() }
        let handle = try #require(owner?.trigger(.run(work, .concurrent)))
        await work.started.wait()
        owner?.trigger(.set(7))
        owner = nil
        #expect(reference == nil)
        #expect(await handle.finish() == .cancelled)
        #expect(await work.read() == 7)
        await work.write(99)
        #expect(await work.read() == 7)
        work.release.open()
        await work.exited.wait()
        #expect(await work.wasCancelled)
    }

    @Test("Owner release before start cancels the handle", arguments: Adapter.supported)
    fileprivate func ownerReleasedBeforeStart(_ adapter: Adapter) async throws {
        var owner: (any FeatureStore)? = adapter.make()
        weak var reference = owner
        defer { reference = nil }
        let work = ControlledWork()
        defer { work.release.open() }
        let handle = try #require(owner?.trigger(.run(work, .concurrent)))
        owner = nil
        #expect(reference == nil)
        #expect(await handle.finish() == .cancelled)
        #expect(await work.starts == 0)
    }

    @Test("Escaped updater is invalidated by cancellation", arguments: Adapter.supported)
    fileprivate func callbackAfterCancel(_ adapter: Adapter) async throws {
        let store = adapter.make()
        let work = ControlledWork()
        defer { work.release.open() }
        let handle = try #require(store.trigger(.run(work, .concurrent)))
        await work.started.wait()
        store.cancel()
        #expect(await handle.finish() == .cancelled)
        await work.write(42)
        #expect(store.state.value == 0)
        #expect(store.activeWorkCount == 0)
    }

    @Test("Escaped updater is invalidated by completion", arguments: Adapter.supported)
    fileprivate func callbackAfterCompletion(_ adapter: Adapter) async throws {
        let store = adapter.make()
        let work = ControlledWork()
        defer { work.release.open() }
        let handle = try #require(store.trigger(.run(work, .concurrent)))
        await work.started.wait()
        work.release.open()
        #expect(await handle.finish() == .completed)
        await work.write(42)
        #expect(store.state.value == 0)
        handle.cancel()
        #expect(await handle.finish() == .completed)
    }

    @Test("Replacement blocks the old callback and preserves new work", arguments: Adapter.supported)
    fileprivate func replacement(_ adapter: Adapter) async throws {
        let store = adapter.make()
        let first = ControlledWork(), second = ControlledWork()
        defer { first.release.open(); second.release.open() }
        let old = try #require(store.trigger(.run(first, .cancelPrevious)))
        await first.started.wait()
        let new = try #require(store.trigger(.run(second, .cancelPrevious)))
        await second.started.wait()
        #expect(await old.finish() == .cancelled)
        await second.write(2)
        await first.write(1)
        #expect(store.state.value == 2)
        first.release.open()
        await first.exited.wait()
        #expect(store.activeWorkCount == 1)
        second.release.open()
        #expect(await new.finish() == .completed)
    }

    @Test("Drop resolves immediately; completed work permits a new request", arguments: Adapter.supported)
    fileprivate func dropAndRestart(_ adapter: Adapter) async throws {
        let store = adapter.make()
        let first = ControlledWork(), second = ControlledWork()
        defer { first.release.open(); second.release.open() }
        let active = try #require(store.trigger(.run(first, .dropWhileRunning)))
        let dropped = try #require(store.trigger(.run(second, .dropWhileRunning)))
        #expect(await dropped.finish() == .dropped)
        #expect(await second.starts == 0)
        first.release.open()
        #expect(await active.finish() == .completed)
        let restarted = try #require(store.trigger(.run(second, .dropWhileRunning)))
        second.release.open()
        #expect(await restarted.finish() == .completed)
        #expect(await second.starts == 1)
    }

    @Test("Cancel asks the Interactor to write leftover state", arguments: Adapter.supported)
    fileprivate func cancelWritesLeftoverState(_ adapter: Adapter) async throws {
        let store = adapter.make()
        let work = ControlledWork()
        defer { work.release.open() }
        let handle = try #require(store.trigger(.run(work, .concurrent)))
        await work.started.wait()
        store.cancel()
        #expect(await handle.finish() == .cancelled)
        await work.write(42)
        #expect(store.state.value == 0)
        #expect(store.state.leftover == -1)
        #expect(store.activeWorkCount == 0)
    }

    @Test("Cancellation before start resolves without executing the operation", arguments: Adapter.supported)
    fileprivate func cancelledBeforeStart(_ adapter: Adapter) async throws {
        let store = adapter.make()
        let work = ControlledWork()
        defer { work.release.open() }
        let handle = try #require(store.trigger(.run(work, .concurrent)))
        store.cancel()
        #expect(await handle.finish() == .cancelled)
        #expect(await work.starts == 0)
    }

    @Test("A plain Work replaces the previous one", arguments: Adapter.supported)
    fileprivate func defaultWorkReplaces(_ adapter: Adapter) async throws {
        let store = adapter.make()
        let first = ControlledWork(), second = ControlledWork()
        defer { first.release.open(); second.release.open() }
        let old = try #require(store.trigger(.runDefault(first)))
        let new = try #require(store.trigger(.runDefault(second)))
        #expect(await old.finish() == .cancelled)
        #expect(await first.starts == 0)
        second.release.open()
        #expect(await new.finish() == .completed)
    }

    @Test("Replacing the slot leaves concurrent work running", arguments: Adapter.supported)
    fileprivate func replaceLeavesConcurrent(_ adapter: Adapter) async throws {
        let store = adapter.make()
        let side = ControlledWork(), first = ControlledWork(), second = ControlledWork()
        defer { side.release.open(); first.release.open(); second.release.open() }
        let sideHandle = try #require(store.trigger(.run(side, .concurrent)))
        await side.started.wait()
        let old = try #require(store.trigger(.run(first, .cancelPrevious)))
        await first.started.wait()
        let new = try #require(store.trigger(.run(second, .cancelPrevious)))
        #expect(await old.finish() == .cancelled)
        #expect(store.activeWorkCount == 2)
        #expect(store.state.leftover == 0)
        side.release.open()
        second.release.open()
        #expect(await sideHandle.finish() == .completed)
        #expect(await new.finish() == .completed)
    }

    @Test("isWorking stays on through replacement and clears on completion", arguments: Adapter.supported)
    fileprivate func isWorkingAcrossReplacement(_ adapter: Adapter) async throws {
        let store = adapter.make()
        let first = ControlledWork(), second = ControlledWork()
        defer { first.release.open(); second.release.open() }
        #expect(!store.isWorking)
        let old = try #require(store.trigger(.runDefault(first)))
        #expect(store.isWorking)
        await first.started.wait()
        let new = try #require(store.trigger(.runDefault(second)))
        #expect(await old.finish() == .cancelled)
        #expect(store.isWorking)
        first.release.open()
        await first.exited.wait()
        #expect(store.isWorking)
        second.release.open()
        #expect(await new.finish() == .completed)
        #expect(!store.isWorking)
    }

    @Test("A dropped duplicate keeps isWorking on", arguments: Adapter.supported)
    fileprivate func isWorkingWithDrop(_ adapter: Adapter) async throws {
        let store = adapter.make()
        let first = ControlledWork(), second = ControlledWork()
        defer { first.release.open(); second.release.open() }
        let active = try #require(store.trigger(.run(first, .dropWhileRunning)))
        let dropped = try #require(store.trigger(.run(second, .dropWhileRunning)))
        #expect(await dropped.finish() == .dropped)
        #expect(store.isWorking)
        first.release.open()
        #expect(await active.finish() == .completed)
        #expect(!store.isWorking)
    }

    @Test("Concurrent work does not set isWorking", arguments: Adapter.supported)
    fileprivate func isWorkingIgnoresConcurrent(_ adapter: Adapter) async throws {
        let store = adapter.make()
        let work = ControlledWork()
        defer { work.release.open() }
        let handle = try #require(store.trigger(.run(work, .concurrent)))
        await work.started.wait()
        #expect(!store.isWorking)
        work.release.open()
        #expect(await handle.finish() == .completed)
    }

    @Test("isWorking clears when a handle is cancelled, even if the work ignores it", arguments: Adapter.supported)
    fileprivate func isWorkingClearsOnHandleCancel(_ adapter: Adapter) async throws {
        let store = adapter.make()
        let work = ControlledWork()
        defer { work.release.open() }
        let handle = try #require(store.trigger(.runDefault(work)))
        await work.started.wait()
        handle.cancel()
        #expect(!store.isWorking)
        #expect(await handle.finish() == .cancelled)
    }

    @Test("isWorking clears when the awaiting task is cancelled", arguments: Adapter.supported)
    fileprivate func isWorkingClearsOnWaiterCancel(_ adapter: Adapter) async throws {
        let store = adapter.make()
        let work = ControlledWork()
        defer { work.release.open() }
        let handle = try #require(store.trigger(.runDefault(work)))
        await work.started.wait()
        let waiter = Task { await handle.finish() }
        waiter.cancel()
        #expect(await waiter.value == .cancelled)
        #expect(!store.isWorking)
    }

    @Test("Full cancel clears isWorking", arguments: Adapter.supported)
    fileprivate func isWorkingClearsOnCancelAll(_ adapter: Adapter) async throws {
        let store = adapter.make()
        let work = ControlledWork()
        defer { work.release.open() }
        let handle = try #require(store.trigger(.runDefault(work)))
        store.cancel()
        #expect(!store.isWorking)
        #expect(await handle.finish() == .cancelled)
    }

    @Test("Cancelling one handle leaves the other work running", arguments: Adapter.supported)
    fileprivate func cancelOneHandle(_ adapter: Adapter) async throws {
        let store = adapter.make()
        let first = ControlledWork(), second = ControlledWork()
        defer { first.release.open(); second.release.open() }
        let a = try #require(store.trigger(.run(first, .concurrent)))
        let b = try #require(store.trigger(.run(second, .concurrent)))
        await first.started.wait()
        await second.started.wait()
        a.cancel()
        #expect(await a.finish() == .cancelled)
        #expect(store.state.leftover == 0)
        second.release.open()
        #expect(await b.finish() == .completed)
    }

    @Test("A cancelled handle immediately allows replacement work", arguments: Adapter.supported)
    fileprivate func handleCancelAndRestart(_ adapter: Adapter) async throws {
        let store = adapter.make()
        let first = ControlledWork(), second = ControlledWork()
        defer { first.release.open(); second.release.open() }
        let a = try #require(store.trigger(.run(first, .dropWhileRunning)))
        await first.started.wait()
        a.cancel()
        let b = try #require(store.trigger(.run(second, .dropWhileRunning)))
        second.release.open()
        #expect(await a.finish() == .cancelled)
        #expect(await b.finish() == .completed)
    }

    @Test("Cancellation of the awaiting task cancels its Work", arguments: Adapter.supported)
    fileprivate func cancelledWaiter(_ adapter: Adapter) async throws {
        let store = adapter.make()
        let work = ControlledWork()
        defer { work.release.open() }
        let handle = try #require(store.trigger(.run(work, .concurrent)))
        await work.started.wait()
        let waiter = Task { await handle.finish() }
        waiter.cancel()
        #expect(await waiter.value == .cancelled)
        await work.write(42)
        #expect(store.state.value == 0)
    }

    @Test("Every waiter receives the terminal outcome", arguments: Adapter.supported)
    fileprivate func multipleWaiters(_ adapter: Adapter) async throws {
        let store = adapter.make()
        let work = ControlledWork()
        defer { work.release.open() }
        let handle = try #require(store.trigger(.run(work, .concurrent)))
        async let a = handle.finish()
        async let b = handle.finish()
        work.release.open()
        #expect(await a == .completed)
        #expect(await b == .completed)
        #expect(await handle.finish() == .completed)
    }

    @Test("Concurrent cancellation and completion resolve every waiter once", arguments: Adapter.supported)
    fileprivate func cancellationRace(_ adapter: Adapter) async throws {
        let store = adapter.make()
        let work = ControlledWork()
        defer { work.release.open() }
        let handle = try #require(store.trigger(.run(work, .concurrent)))
        await work.started.wait()
        let results = await withTaskGroup(of: WorkOutcome.self, returning: [WorkOutcome].self) { group in
            for _ in 0..<16 { group.addTask { await handle.finish() } }
            group.addTask {
                handle.cancel()
                return await handle.finish()
            }
            work.release.open()
            var results: [WorkOutcome] = []
            for await outcome in group { results.append(outcome) }
            return results
        }
        #expect(results.count == 17)
        let outcome = await handle.finish()
        #expect(outcome == .completed || outcome == .cancelled)
        #expect(results.allSatisfy { $0 == outcome })
    }

    #if canImport(Observation)
    @Test("Observation still invalidates tracked state")
    func observationInvalidation() async {
        guard #available(iOS 17, macOS 14, tvOS 17, *) else { return }
        let owner = ObservableViewState(FeatureInteractor())
        let changed = Signal()
        withObservationTracking {
            _ = owner.state.value
        } onChange: {
            changed.open()
        }
        owner.trigger(.set(3))
        await changed.wait()
        #expect(owner.state.value == 3)
    }
    #endif
}
