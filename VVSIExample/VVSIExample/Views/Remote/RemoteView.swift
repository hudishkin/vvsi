import SwiftUI
import VVSI

/// Remote list feature: load products and pull-to-refresh; progress via events.
struct RemoteView: View {

    @StateObject
    private var viewState = ViewState(.init(items: []), Interactor())

    @State
    private var infoText = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
                Text(infoText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                ForEach(viewState.state.items, id: \.id) { product in
                    HStack {
                        AsyncImage(url: URL(string: product.image)) { result in
                            result.image?
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
            .padding()
        }
        .onAppear {
            viewState.trigger(.load)
        }
        .onReceive(viewState.events) { event in
            switch event {
            case .event(let text):
                infoText = text
            }
        }
        .refreshable {
            await withCheckedContinuation { continuation in
                viewState.trigger(.refresh {
                    continuation.resume()
                })
            }
        }
        .onDisappear {
            viewState.cancel()
        }
    }
}

#Preview {
    RemoteView()
}
