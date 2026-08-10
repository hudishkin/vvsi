import VVSI

extension RemoteView {

    struct VState: StateProtocol {

        struct Product {
            let id: Int
            let title: String
            let image: String
        }

        var items: [Product]
    }

    enum VAction: ActionProtocol {
        case load
        case refresh(@Sendable () -> Void)
    }

    enum VEvent: EventProtocol {
        case event(String)
    }
}
