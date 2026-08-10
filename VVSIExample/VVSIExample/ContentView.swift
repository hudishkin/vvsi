import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("List") {
                    ListView()
                }
                NavigationLink("Remote") {
                    RemoteView()
                }
                if #available(iOS 17, macOS 14, *) {
                    NavigationLink("Observable List") {
                        ObservableListView()
                    }
                }
            }
            .navigationTitle("VVSI Example")
        }
    }
}

#Preview {
    ContentView()
}
