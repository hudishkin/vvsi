import VVSI

extension ListView {

    struct Options {
        let count: Int
        let length: Int
    }

    struct VState: StateProtocol {
        var items: [String] = []
    }

    enum VAction: ActionProtocol {
        case add
        case remove
        case random(Options)
    }

    enum VEvent: EventProtocol {
        case error(String)
    }
}
