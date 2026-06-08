import Foundation

/// Protocol abstracting the models.dev API for testability.
public protocol ModelsDevAPI {
    func fetchProviders() async throws -> ModelsDevResponse
}

/// Fetches LLM provider/model pricing from models.dev/api.json.
public final class ModelsDevAPIService: ModelsDevAPI {
    private let url = URL(string: "https://models.dev/api.json")!
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchProviders() async throws -> ModelsDevResponse {
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ModelsDevAPIError.invalidResponse
        }

        let decoder = JSONDecoder()
        return try decoder.decode(ModelsDevResponse.self, from: data)
    }
}

public enum ModelsDevAPIError: Error {
    case invalidResponse
}
