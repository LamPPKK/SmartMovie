import Foundation

public enum CatalogSearchMode: String, CaseIterable, Identifiable, Sendable {
    case catalog
    case externalID

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .catalog: String(localized: "Catalog", bundle: .module)
        case .externalID: String(localized: "External ID", bundle: .module)
        }
    }
}

public enum ExternalIDSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case imdb = "imdb_id"
    case tvdb = "tvdb_id"
    case wikidata = "wikidata_id"
    case facebook = "facebook_id"
    case instagram = "instagram_id"
    case twitter = "twitter_id"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .imdb: "IMDb"
        case .tvdb: "TheTVDB"
        case .wikidata: "Wikidata"
        case .facebook: "Facebook"
        case .instagram: "Instagram"
        case .twitter: "X / Twitter"
        }
    }

    public var example: String {
        switch self {
        case .imdb: "tt0133093"
        case .tvdb: "73739"
        case .wikidata: "Q83495"
        case .facebook: "TheMatrixMovie"
        case .instagram: "thematrixmovie"
        case .twitter: "TheMatrixMovie"
        }
    }
}

public struct ExternalIDFindResult: Codable, Sendable {
    public let source: ExternalIDSource
    public let externalID: String
    public let results: [CatalogEntity]

    private enum CodingKeys: String, CodingKey {
        case source
        case externalID = "externalId"
        case results
    }
}
