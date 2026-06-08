import Foundation

/// Top-level response from models.dev/api.json.
/// Dictionary key is the provider slug, value is the provider info.
public typealias ModelsDevResponse = [String: ModelsDevProvider]

public struct ModelsDevProvider: Decodable {
    public let id: String
    public let name: String
    public let models: [String: ModelsDevModel]
}

public struct ModelsDevModel: Decodable {
    public let id: String
    public let name: String
    public let cost: ModelsDevCost?
}

public struct ModelsDevCost: Decodable {
    public let input: Double
    public let output: Double
    /// Optional: cache_read price per 1M tokens.
    public let cacheRead: Double?

    enum CodingKeys: String, CodingKey {
        case input
        case output
        case cacheRead = "cache_read"
    }
}
