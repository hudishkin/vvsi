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

    enum VNotification: NotificationProtocol {
        case event(String)
    }

    final class Interactor: ViewStateInteractorProtocol {

        typealias S = VState
        typealias A = VAction
        typealias N = VNotification

        let notifications: PassthroughSubject<N, Never> = .init()

        init() { }

        func execute(
            _ state: @escaping CurrentState<S>,
            _ action: A,
            _ updater: @escaping StateUpdater<S>
        ) {
            switch action {
            case .mutate(let value, let callback):
                Task {
                    await updater {
                        $0.value = value
                    }
                    callback(await state())
                }
            }
        }
    }

}


struct VVSIExampleTests {

    @Test
    func mutateState() async throws {
        let viewState = ViewState(TestView.VState.init(value: 0), TestView.Interactor())

        #expect(viewState.state.value == 0)

        await viewState.trigger(.mutate(42, { after in
            #expect(after.value == 42)

            Task {
                try await Task.sleep(nanoseconds: 100)
                #expect(viewState.state.value == 0)
            }
        }))

        await viewState.trigger(.mutate(0, { after in
            #expect(after.value == 0)
        }))
        try await Task.sleep(nanoseconds: 100000)
        #expect(viewState.state.value == 0)
    }


    @Test
    func publishState() async throws {
        let viewState = ViewState(TestView.VState.init(value: 0), TestView.Interactor())

        var values = Array(1...50)
        var result = [Int]()
        let cancel = viewState.$state.sink { state in
            result.append(state.value)
        }
        for value in values {
            await viewState.trigger(.mutate(value, { after in }))
        }
        try await Task.sleep(nanoseconds: 10000000)

        #expect(values.count == result.count - 1)
    }

}
