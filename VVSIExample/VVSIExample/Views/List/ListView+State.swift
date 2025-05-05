//
//  ListView+State.swift
//  VVSIExample
//
//  Created by Simon Hudishkin on 16.02.2025.
//

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

    enum VNotification: NotificationProtocol {
        case error(String)
    }

}
