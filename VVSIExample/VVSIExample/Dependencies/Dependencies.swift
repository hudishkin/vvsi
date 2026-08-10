//
//  Dependencies.swift
//  VVSIExample
//
//  Created by Simon Hudishkin on 05.05.2025.
//

/// Example DI container. Real apps usually use a proper dependency graph.
class Dependencies {

    static let shared: Dependencies = .init(service: .init())

    class Service { }

    var service: Service

    init(service: Service) {
        self.service = service
    }

}
