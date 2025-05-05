//
//  ListView.swift
//  VVSIExample
//
//  Created by Simon Hudishkin on 16.02.2025.
//

import SwiftUI
import VVSI

struct RemoteView: View {

    @StateObject
    var viewState = ViewState(.init(items: []), Interactor())

    @State
    var infoText: String = ""

    var body: some View {

        ScrollView {
            LazyVStack(alignment: .leading) {
                Text(infoText)
                    .font(.caption2)
                    .foregroundColor(.gray)

                ForEach(viewState.state.items, id: \.id) { product in
                    HStack() {
                        AsyncImage(url: URL(string: product.image)) { result in
                            result
                                .image?
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        }
                        .frame(width: 40, height: 80)

                        Text(product.title)
                            .multilineTextAlignment(.leading)
                            .font(.caption2)
                    }
                }
            }
        }
        .onAppear {
            viewState.trigger(.load)
        }
        .onReceive(viewState.notifications) { notification in
            switch notification {
            case .event(let text):
                infoText = text
            }
        }
        .refreshable {
            await withCheckedContinuation { continuation in
                viewState.trigger(.refresh({
                    continuation.resume(returning: ())
                }))
            }
        }
    }
}

#Preview {
    RemoteView()
}
