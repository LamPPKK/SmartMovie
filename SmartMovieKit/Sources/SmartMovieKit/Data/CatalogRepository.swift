import Foundation

public struct RemoteCatalogRepository: CatalogRepository {
    let client: APIClient

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
            URLQueryItem(name: "vote_average_gte", value: String(format: "%.1f", filter.minimumRating)),
            URLQueryItem(name: "include_adult", value: String(filter.includeAdult))
        ]
        if !filter.genres.isEmpty {
            query.append(URLQueryItem(name: "genres", value: filter.genres.sorted().map(String.init).joined(separator: ",")))
        }
        if let year = filter.year {
            query.append(URLQueryItem(name: "year", value: String(year)))
        }
        append(filter.releaseDateFrom, named: "release_date_gte", to: &query)
        append(filter.releaseDateThrough, named: "release_date_lte", to: &query)
        append(filter.originalLanguage?.lowercased(), named: "original_language", to: &query)
        append(filter.originCountry?.uppercased(), named: "origin_country", to: &query)
        if let runtime = filter.minimumRuntime { query.append(URLQueryItem(name: "runtime_gte", value: String(runtime))) }
        if let runtime = filter.maximumRuntime { query.append(URLQueryItem(name: "runtime_lte", value: String(runtime))) }
        if filter.minimumVoteCount > 0 {
            query.append(URLQueryItem(name: "vote_count_gte", value: String(filter.minimumVoteCount)))
        }
        if let region = filter.region?.uppercased() {
            query.append(URLQueryItem(name: "region", value: region))
            if !filter.watchProviderIDs.isEmpty || !filter.monetizationTypes.isEmpty {
                query.append(URLQueryItem(name: "watch_region", value: region))
            }
        }
        if mediaType == .movie {
            append(filter.certificationCountry?.uppercased(), named: "certification_country", to: &query)
            append(filter.certificationMinimum, named: "certification_gte", to: &query)
            append(filter.certificationMaximum, named: "certification_lte", to: &query)
        }
        if !filter.watchProviderIDs.isEmpty {
            query.append(URLQueryItem(
                name: "watch_providers",
                value: filter.watchProviderIDs.sorted().map(String.init).joined(separator: "|")
            ))
        }
        if !filter.monetizationTypes.isEmpty {
            query.append(URLQueryItem(
                name: "watch_monetization_types",
                value: filter.monetizationTypes.map(\.rawValue).sorted().joined(separator: "|")
            ))
        }
        return try await client.get("v2/discover/\(mediaType.rawValue)", queryItems: query)
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

private func append(_ value: String?, named name: String, to query: inout [URLQueryItem]) {
    guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines), !normalized.isEmpty else { return }
    query.append(URLQueryItem(name: name, value: normalized))
}

private struct GenreResponse: Decodable {
    let genres: [Genre]
}
