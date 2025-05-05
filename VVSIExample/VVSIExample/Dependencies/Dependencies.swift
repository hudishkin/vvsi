//
//  Dependencies.swift
//  VVSIExample
//
//  Created by Simon Hudishkin on 05.05.2025.
//

// INFO: - For example. In a real application, the code might be different
class Dependencies {

    static let shared: Dependencies = .init(service: .init())

    class Service { }

    var service: Service

    init(service: Service) {
        self.service = service
    }

}
