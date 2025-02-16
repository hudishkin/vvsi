//
//  ListView+State.swift
//  VVSIExample
//
//  Created by Simon Hudishkin on 16.02.2025.
//

import VVSI

extension ListView {

    struct VState: StateProtocol {
        var items: [String]
    }

    enum VAction: ActionProtocol {
        case add
        case remove
    }

    enum VNotification: NotificationProtocol {

    }

}
