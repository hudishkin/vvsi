import Foundation
import VVSI

extension ListView {

    struct Options {
        let count: Int
        let length: Int
    }

    struct VState: StateProtocol {
        struct Item: Identifiable, Sendable {
            let id = UUID()
            let title: String
        }

        var items: [Item] = []
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
