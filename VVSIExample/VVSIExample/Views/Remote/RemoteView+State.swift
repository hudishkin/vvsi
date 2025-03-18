//
//  ListView+State.swift
//  VVSIExample
//
//  Created by Simon Hudishkin on 16.02.2025.
//

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
        case refresh(() -> Void)
    }

    enum VNotification: NotificationProtocol {
        case event(String)
    }

}
