//
//  ListView.swift
//  VVSIExample
//
//  Created by Simon Hudishkin on 16.02.2025.
//

import SwiftUI
import VVSI

struct ListView: View {

    enum AlertType: Identifiable {
        var id: String { "\(self)" }
        case error(String)
    }

    @StateObject
    var viewState = ViewState(Interactor())

    /*
    @StateObject
    var viewState = ViewState(.init(), Interactor())
    */

    @State
    private var alertType: AlertType? = nil

    var body: some View {

        ForEach(viewState.state.items, id: \.self) { item in
            Text(item)
        }

        HStack {
            Button {
                viewState.trigger(.add)
            } label: {
                Text("Add")
            }

            Button {
                viewState.trigger(.remove)
            } label: {
                Text("Remove")
            }
            Button {
                viewState.trigger(.random(.init(count: Int.random(in: 1..<10), length: Int.random(in: 1..<5))))
            } label: {
                Text("Random")
            }
        }
        .alert(item: $alertType) { item in
            switch item {
            case .error(let error):
                Alert(
                    title: Text("Error"),
                    message: Text(error),
                    dismissButton: .default(Text("Ok"))
                )
            }
        }
        .onReceive(viewState.notifications) { notification in
            switch notification {
            case .error(let message):
                alertType = .error(message)
            }
        }
    }

}

#Preview {
    ListView()
}
