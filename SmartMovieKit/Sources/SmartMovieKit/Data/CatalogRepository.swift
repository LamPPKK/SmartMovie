import Foundation

public struct RemoteCatalogRepository: CatalogRepository {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func home(mediaType: MediaType, language: String) async throws -> HomeFeed {
        try await client.get("v1/home", queryItems: [
            URLQueryItem(name: "media_type", value: mediaType.rawValue),
            URLQueryItem(name: "language", value: language)
        ])
    }

    public func genres(mediaType: MediaType, language: String) async throws -> [Genre] {
        let response: GenreResponse = try await client.get("v1/genres/\(mediaType.rawValue)", queryItems: [
            URLQueryItem(name: "language", value: language)
        ])
        return response.genres
    }

    public func discover(
        mediaType: MediaType,
        filter: DiscoverFilter,
        page: Int,
        language: String
    ) async throws -> PagedResult<TitleSummary> {
        var query = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "sort_by", value: filter.sort.rawValue),
            URLQueryItem(name: "vote_average_gte", value: String(format: "%.1f", filter.minimumRating))
        ]
        if !filter.genres.isEmpty {
            query.append(URLQueryItem(name: "genre_ids", value: filter.genres.sorted().map(String.init).joined(separator: ",")))
        }
        if let year = filter.year {
            query.append(URLQueryItem(name: "year", value: String(year)))
        }
        return try await client.get("v1/discover/\(mediaType.rawValue)", queryItems: query)
    }

    public func search(
        query: String,
        scope: SearchScope,
        page: Int,
        language: String
    ) async throws -> PagedResult<TitleSummary> {
        try await client.get("v1/search", queryItems: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "scope", value: scope.rawValue),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "language", value: language)
        ])
    }

    public func detail(mediaType: MediaType, id: Int, language: String) async throws -> TitleDetail {
        try await client.get("v1/titles/\(mediaType.rawValue)/\(id)", queryItems: [
            URLQueryItem(name: "language", value: language)
        ])
    }

    public func imageConfiguration() async throws -> ImageConfiguration {
        try await client.get("v1/configuration")
    }
}

private struct GenreResponse: Decodable {
    let genres: [Genre]
}
