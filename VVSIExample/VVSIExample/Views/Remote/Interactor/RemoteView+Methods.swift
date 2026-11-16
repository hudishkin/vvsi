import Foundation

extension RemoteView.Interactor {

    static func fetchData() async throws -> [ProductDTO] {
        let url = URL(string: "https://fakestoreapi.com/products")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([ProductDTO].self, from: data)
    }

    struct ProductDTO: Codable, Sendable {
        let id: Int
        let title: String
        let price: Double
        let description: String
        let category: String
        let image: String
    }
}
