//
//  ListView.swift
//  VVSIExample
//
//  Created by Simon Hudishkin on 16.02.2025.
//

import SwiftUI
import VVSI

struct ListView: View {

    @StateObject
    var viewState = ViewState<VState, VAction, VNotification>(.init(), Interactor())

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
        }
    }

}

#Preview {
    ListView()
}
