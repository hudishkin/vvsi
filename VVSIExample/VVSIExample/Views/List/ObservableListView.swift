import SwiftUI
import VVSI

/// Experimental `@Observable` ViewState demo (iOS 17+ / macOS 14+).
@available(iOS 17, macOS 14, *)
struct ObservableListView: View {

    enum AlertType: Identifiable {
        var id: String { "\(self)" }
        case error(String)
    }

    @State
    private var viewState = ObservableViewState(ListView.Interactor())

    @State
    private var alertType: AlertType?

    var body: some View {
        VStack(spacing: 16) {
            Text("ObservableViewState")
                .font(.headline)

            ForEach(viewState.state.items, id: \.self) { item in
                Text(item)
            }

            HStack {
                Button("Add") { viewState.trigger(.add) }
                Button("Remove") { viewState.trigger(.remove) }
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
        .onDisappear {
            viewState.cancel()
        }
    }
}

#Preview {
    if #available(iOS 17, macOS 14, *) {
        ObservableListView()
    }
}
