import VVSI

extension RemoteView {

    struct VState: StateProtocol {

        struct Product: Sendable {
            let id: Int
            let title: String
            let image: String
        }

        var items: [Product]
    }

    enum VAction: ActionProtocol {
        case load
        case refresh
    }

    enum VEvent: EventProtocol {
        case event(String)
    }
}
