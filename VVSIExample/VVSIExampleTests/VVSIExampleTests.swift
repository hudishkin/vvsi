//
//  VVSIExampleTests.swift
//  VVSIExampleTests
//
//  Created by Simon Hudishkin on 24.03.2025.
//

import Testing
import Combine


@testable import VVSI
@testable import VVSIExample


struct TestView {

    struct VState: StateProtocol {
        var value: Int
    }

    enum VAction: ActionProtocol {
        case mutate(Int, (VState) -> Void)
    }

    enum VEvent: EventProtocol {
        case event(String)
    }

    final class Interactor: ViewStateInteractorProtocol {

        typealias S = VState
        typealias A = VAction
        typealias N = VEvent

        let events = EventPipe<N>()

        init() { }

        @MainActor
        func reduce(_ state: inout S, _ action: A) -> Work<S>? {
            switch action {
            case .mutate(let value, let callback):
                state.value = value
                callback(state)
            }
            return nil
        }
    }

}


struct VVSIExampleTests {

    @Test
    @MainActor
    func mutateState() {
        let viewState = ViewState(TestView.VState.init(value: 0), TestView.Interactor())

        #expect(viewState.state.value == 0)

        viewState.trigger(.mutate(42, { after in
            #expect(after.value == 42)
        }))

        viewState.trigger(.mutate(0, { after in
            #expect(after.value == 0)
        }))
        #expect(viewState.state.value == 0)
    }


    @Test
    @MainActor
    func publishState() {
        let viewState = ViewState(TestView.VState.init(value: 0), TestView.Interactor())

        let values = Array(1...50)
        var result = [Int]()
        let cancel = viewState.$state.sink { state in
            result.append(state.value)
        }
        for value in values {
            viewState.trigger(.mutate(value, { _ in }))
        }

        #expect(values.count == result.count - 1)
        _ = cancel
    }

}

@Suite("Remote example", .timeLimit(.minutes(1)))
@MainActor
struct RemoteExampleTests {
    @Test("Refresh cancellation before start always resolves the handle")
    func cancelBeforeStart() async throws {
        let interactor = RemoteView.Interactor(fetchProducts: {
            Issue.record("Cancelled work must not start a request")
            return []
        })
        let state = ViewState(RemoteView.VState(items: []), interactor)
        let handle = try #require(state.trigger(.refresh))
        #expect(state.isWorking)
        state.cancel()
        #expect(await handle.finish() == .cancelled)
        #expect(!state.isWorking)
    }

    @Test("Successful refresh installs products and clears loading")
    func success() async throws {
        let product = RemoteView.Interactor.ProductDTO(
            id: 1, title: "Test", price: 1, description: "Test product",
            category: "Tests", image: "https://example.com/image.png"
        )
        let state = ViewState(RemoteView.VState(items: []), RemoteView.Interactor(fetchProducts: { [product] }))
        let handle = try #require(state.trigger(.refresh))
        #expect(await handle.finish() == .completed)
        #expect(state.state.items.map(\.id) == [1])
        #expect(!state.isWorking)
    }

    @Test("A failed refresh preserves existing content and sends an error")
    func failure() async throws {
        struct FetchError: Error {}
        let state = ViewState(
            RemoteView.VState(items: [.init(id: 1, title: "Existing", image: "")]),
            RemoteView.Interactor(fetchProducts: { throw FetchError() })
        )
        var events = state.eventStream().makeAsyncIterator()
        let handle = try #require(state.trigger(.refresh))
        #expect(await handle.finish() == .completed)
        #expect(state.state.items.map(\.id) == [1])
        #expect(!state.isWorking)
        if case .event(let message) = await events.next() {
            #expect(message.contains("Could not load"))
        } else {
            Issue.record("Expected an error event")
        }
    }

    @Test("Equal list titles have independent identities")
    func listIdentity() {
        let state = ViewState(ListView.Interactor())
        state.trigger(.add)
        state.trigger(.add)
        #expect(state.state.items.suffix(2).map(\.title) == ["New item", "New item"])
        #expect(Set(state.state.items.map(\.id)).count == state.state.items.count)
    }
}
