//
//  VVSIExampleTests.swift
//  VVSIExampleTests
//
//  Created by Simon Hudishkin on 24.03.2025.
//

import Testing
import Combine


@testable import VVSI


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
