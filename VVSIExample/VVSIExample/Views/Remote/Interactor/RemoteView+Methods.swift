import Foundation

extension RemoteView.Interactor {

    func fetchData() async throws -> [Product] {
        let url = URL(string: "https://fakestoreapi.com/products")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([Product].self, from: data)
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
