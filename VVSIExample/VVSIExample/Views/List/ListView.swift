import SwiftUI
import VVSI

/// Local list feature: add / remove / random items with a hard limit via events.
struct ListView: View {

    enum AlertType: Identifiable {
        var id: String { "\(self)" }
        case error(String)
    }

    @StateObject
    private var viewState = ViewState(Interactor())

    @State
    private var alertType: AlertType?

    var body: some View {
        VStack(spacing: 16) {
            ForEach(viewState.state.items, id: \.self) { item in
                Text(item)
            }

            HStack {
                Button("Add") {
                    viewState.trigger(.add)
                }
                Button("Remove") {
                    viewState.trigger(.remove)
                }
                Button("Random") {
                    viewState.trigger(.random(.init(
                        count: Int.random(in: 1..<10),
                        length: Int.random(in: 1..<5)
                    )))
                }
            }
        }
        .padding()
        .alert(item: $alertType) { item in
            switch item {
            case .error(let message):
                Alert(
                    title: Text("Error"),
                    message: Text(message),
                    dismissButton: .default(Text("Ok"))
                )
            }
        }
        .onReceive(viewState.events) { event in
            switch event {
            case .error(let message):
                alertType = .error(message)
            }
        }
    }
}

#Preview {
    ListView()
}
