import Foundation

extension RemoteCatalogRepository: CatalogV2Repository {
    public func capabilities() async throws -> CapabilitiesV2 {
        try await client.get("v2/capabilities")
    }

    public func discoverConfiguration(language: String, region: String?) async throws -> DiscoverConfiguration {
        var queryItems = [URLQueryItem(name: "language", value: language)]
        if let region { queryItems.append(URLQueryItem(name: "region", value: region)) }
        return try await client.get("v2/configuration", queryItems: queryItems)
    }

    public func trending(
        kind: String,
        window: String,
        page: Int,
        language: String,
        includeAdult: Bool
    ) async throws -> PagedResult<CatalogEntity> {
        try await client.get("v2/trending/\(kind)/\(window)", queryItems: [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "include_adult", value: String(includeAdult))
        ])
    }

    public func searchEntities(_ request: EntitySearchRequest) async throws -> PagedResult<CatalogEntity> {
        var queryItems = [
            URLQueryItem(name: "query", value: request.query),
            URLQueryItem(name: "scope", value: request.scope.rawValue),
            URLQueryItem(name: "page", value: String(request.page)),
            URLQueryItem(name: "language", value: request.language),
            URLQueryItem(name: "include_adult", value: String(request.includeAdult))
        ]
        if let region = request.region { queryItems.append(URLQueryItem(name: "region", value: region)) }
        return try await client.get("v2/search", queryItems: queryItems)
    }

    public func findExternalID(
        _ externalID: String,
        source: ExternalIDSource,
        language: String
    ) async throws -> ExternalIDFindResult {
        try await client.get("v2/find/\(externalID)", queryItems: [
            URLQueryItem(name: "source", value: source.rawValue),
            URLQueryItem(name: "language", value: language)
        ])
    }

    public func deepDetail(
        mediaType: MediaType,
        id: Int,
        language: String,
        region: String?,
        includeAdult: Bool
    ) async throws -> TitleDetailV2 {
        var queryItems = [
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "include_adult", value: String(includeAdult))
        ]
        if let region { queryItems.append(URLQueryItem(name: "region", value: region)) }
        return try await client.get("v2/titles/\(mediaType.rawValue)/\(id)", queryItems: queryItems)
    }

    public func person(id: Int, language: String) async throws -> PersonDetail {
        try await client.get("v2/entities/person/\(id)", queryItems: [URLQueryItem(name: "language", value: language)])
    }

    public func collection(id: Int, language: String) async throws -> CollectionDetail {
        try await client.get("v2/entities/collection/\(id)", queryItems: [URLQueryItem(name: "language", value: language)])
    }

    public func organization(kind: EntityKind, id: Int, language: String, page: Int) async throws -> OrganizationDetail {
        guard kind == .company || kind == .network else { throw APIError.notFound }
        return try await client.get("v2/entities/\(kind.rawValue)/\(id)", queryItems: [
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "page", value: String(page))
        ])
    }

    public func keyword(id: Int, language: String, page: Int) async throws -> KeywordDetail {
        try await client.get("v2/entities/keyword/\(id)", queryItems: [
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "page", value: String(page))
        ])
    }

    public func season(seriesID: Int, number: Int, language: String) async throws -> SeasonDetail {
        try await client.get("v2/tv/\(seriesID)/seasons/\(number)", queryItems: [URLQueryItem(name: "language", value: language)])
    }

    public func episode(seriesID: Int, season: Int, number: Int, language: String) async throws -> EpisodeDetail {
        try await client.get(
            "v2/tv/\(seriesID)/seasons/\(season)/episodes/\(number)",
            queryItems: [URLQueryItem(name: "language", value: language)]
        )
    }

    public func credit(id: String, language: String) async throws -> CreditDetail {
        try await client.get(
            "v2/credits/\(id)",
            queryItems: [URLQueryItem(name: "language", value: language)]
        )
    }
}
