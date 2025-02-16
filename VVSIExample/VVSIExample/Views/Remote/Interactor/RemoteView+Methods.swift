//
//  RemoteView+Interactor.swift
//  VVSIExample
//
//  Created by Simon Hudishkin on 16.02.2025.
//

import Foundation

extension RemoteView.Interactor {

    func fetchData() async throws -> [Product] {
        let url = URL(string: "https://fakestoreapi.com/products")!

        let data = try await URLSession.shared.data(from: url)
        let products = try JSONDecoder().decode([Product].self, from: data.0)
        return products
    }

    struct Product: Codable {
        let id: Int
        let title: String
        let price: Double
        let description: String
        let category: String
        let image: String
    }
}

