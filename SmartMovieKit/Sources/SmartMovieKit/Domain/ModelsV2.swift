import Foundation

public enum EntityKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case movie
    case tv
    case person
    case collection
    case company
    case network
    case keyword
    case season
    case episode

    public var id: String { rawValue }
}

public enum SearchScopeV2: String, Codable, CaseIterable, Identifiable, Sendable {
    case all
    case movie
    case tv
    case person
    case collection
    case company
    case keyword

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all: String(localized: "All", bundle: .module)
        case .movie: String(localized: "Movies", bundle: .module)
        case .tv: String(localized: "TV Series", bundle: .module)
        case .person: String(localized: "People", bundle: .module)
        case .collection: String(localized: "Collections", bundle: .module)
        case .company: String(localized: "Companies", bundle: .module)
        case .keyword: String(localized: "Keywords", bundle: .module)
        }
    }
}

public struct PersonSummary: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let profilePath: String?
    public let knownForDepartment: String?
    public let popularity: Double
    public let knownFor: [TitleSummary]
}

public struct CollectionSummary: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let overview: String
    public let posterPath: String?
    public let backdropPath: String?
}

public struct OrganizationSummary: Codable, Hashable, Identifiable, Sendable {
    public let entityKind: EntityKind
    public let id: Int
    public let name: String
    public let logoPath: String?
    public let originCountry: String?
}

public struct KeywordSummary: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let name: String
}

public struct SeasonSummary: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let seasonNumber: Int
    public let name: String
    public let overview: String
    public let posterPath: String?
    public let airDate: String?
    public let voteAverage: Double?
    public let episodeCount: Int
}

public struct EpisodeSummary: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let seriesId: Int
    public let seasonNumber: Int
    public let episodeNumber: Int
    public let name: String
    public let overview: String
    public let stillPath: String?
    public let airDate: String?
    public let runtimeMinutes: Int?
    public let voteAverage: Double?

    public var episodeKey: String { "\(seriesId):\(seasonNumber):\(episodeNumber)" }
}

public enum CatalogEntity: Codable, Hashable, Identifiable, Sendable {
    case title(TitleSummary)
    case person(PersonSummary)
    case collection(CollectionSummary)
    case organization(OrganizationSummary)
    case keyword(KeywordSummary)
    case season(SeasonSummary)
    case episode(EpisodeSummary)

    public var id: String {
        switch self {
        case .title(let value): "\(value.mediaType.rawValue):\(value.id)"
        case .person(let value): "person:\(value.id)"
        case .collection(let value): "collection:\(value.id)"
        case .organization(let value): "\(value.entityKind.rawValue):\(value.id)"
        case .keyword(let value): "keyword:\(value.id)"
        case .season(let value): "season:\(value.id)"
        case .episode(let value): "episode:\(value.id)"
        }
    }

    public var kind: EntityKind {
        switch self {
        case .title(let value): value.mediaType == .movie ? .movie : .tv
        case .person: .person
        case .collection: .collection
        case .organization(let value): value.entityKind
        case .keyword: .keyword
        case .season: .season
        case .episode: .episode
        }
    }

    public var displayName: String {
        switch self {
        case .title(let value): value.displayTitle
        case .person(let value): value.name
        case .collection(let value): value.name
        case .organization(let value): value.name
        case .keyword(let value): value.name
        case .season(let value): value.name
        case .episode(let value): value.name
        }
    }

    private enum CodingKeys: String, CodingKey { case entityKind }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(EntityKind.self, forKey: .entityKind)
        switch kind {
        case .movie, .tv: self = .title(try TitleSummary(from: decoder))
        case .person: self = .person(try PersonSummary(from: decoder))
        case .collection: self = .collection(try CollectionSummary(from: decoder))
        case .company, .network: self = .organization(try OrganizationSummary(from: decoder))
        case .keyword: self = .keyword(try KeywordSummary(from: decoder))
        case .season: self = .season(try SeasonSummary(from: decoder))
        case .episode: self = .episode(try EpisodeSummary(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .title(let value): try value.encode(to: encoder)
        case .person(let value): try value.encode(to: encoder)
        case .collection(let value): try value.encode(to: encoder)
        case .organization(let value): try value.encode(to: encoder)
        case .keyword(let value): try value.encode(to: encoder)
        case .season(let value): try value.encode(to: encoder)
        case .episode(let value): try value.encode(to: encoder)
        }
    }
}

public struct CapabilitiesV2: Codable, Sendable {
    public struct AdultContent: Codable, Sendable {
        public let supported: Bool
        public let defaultEnabled: Bool
        public let localPinRequired: Bool

        public init(supported: Bool, defaultEnabled: Bool, localPinRequired: Bool) {
            self.supported = supported
            self.defaultEnabled = defaultEnabled
            self.localPinRequired = localPinRequired
        }
    }

    public let apiVersion: String
    public let releaseTrain: String
    public let catalog: [String: Bool]
    public let account: [String: Bool]
    public let supportedLanguages: [String]
    public let supportedEntityKinds: [EntityKind]
    public let adultContent: AdultContent

    public init(
        apiVersion: String,
        releaseTrain: String,
        catalog: [String: Bool],
        account: [String: Bool] = [:],
        supportedLanguages: [String] = [],
        supportedEntityKinds: [EntityKind] = [],
        adultContent: AdultContent = AdultContent(supported: false, defaultEnabled: false, localPinRequired: true)
    ) {
        self.apiVersion = apiVersion
        self.releaseTrain = releaseTrain
        self.catalog = catalog
        self.account = account
        self.supportedLanguages = supportedLanguages
        self.supportedEntityKinds = supportedEntityKinds
        self.adultContent = adultContent
    }

    public func supportsCatalog(_ capability: String) -> Bool { catalog[capability] == true }
    public func supportsAccount(_ capability: String) -> Bool { account[capability] == true }
}

public struct Credit: Codable, Hashable, Sendable {
    public let creditId: String?
    public let id: Int?
    public let mediaType: MediaType?
    public let title: String?
    public let character: String?
    public let job: String?
    public let department: String?
    public let profilePath: String?
    public let posterPath: String?
    public let order: Int?
    public let episodeCount: Int?
    public let adult: Bool?
}

public struct ImageAsset: Codable, Hashable, Sendable {
    public let kind: String
    public let filePath: String
    public let aspectRatio: Double
    public let height: Int
    public let width: Int
    public let language: String?
    public let voteAverage: Double
}

public struct ProviderOffer: Codable, Hashable, Identifiable, Sendable {
    public var id: Int { providerId }
    public let providerId: Int
    public let providerName: String
    public let logoPath: String?
    public let displayPriority: Int
}

public struct WatchProviderOption: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let logoPath: String?
    public let displayPriority: Int
}

public struct ConfigurationCountry: Codable, Hashable, Identifiable, Sendable {
    public let code: String
    public let englishName: String
    public let nativeName: String?

    public var id: String { code }
    public var displayName: String { nativeName?.isEmpty == false ? nativeName ?? englishName : englishName }

    private enum CodingKeys: String, CodingKey {
        case code = "iso31661"
        case englishName
        case nativeName
    }
}

public struct ConfigurationLanguage: Codable, Hashable, Identifiable, Sendable {
    public let code: String
    public let englishName: String
    public let name: String?

    public var id: String { code }
    public var displayName: String { name?.isEmpty == false ? name ?? englishName : englishName }

    private enum CodingKeys: String, CodingKey {
        case code = "iso6391"
        case englishName
        case name
    }
}

public struct WatchProviderOptions: Codable, Hashable, Sendable {
    public let movie: [WatchProviderOption]
    public let tv: [WatchProviderOption]

    public func values(for mediaType: MediaType) -> [WatchProviderOption] {
        mediaType == .movie ? movie : tv
    }
}

public struct DiscoverConfiguration: Codable, Hashable, Sendable {
    public let countries: [ConfigurationCountry]
    public let languages: [ConfigurationLanguage]
    public let watchProviderRegions: [ConfigurationCountry]
    public let region: String?
    public let watchProviders: WatchProviderOptions?
}

public struct ProviderRegion: Codable, Hashable, Identifiable, Sendable {
    public var id: String { region }
    public let region: String
    public let tmdbUrl: String?
    public let attribution: String
    public let stream: [ProviderOffer]
    public let rent: [ProviderOffer]
    public let buy: [ProviderOffer]
    public let ads: [ProviderOffer]
    public let free: [ProviderOffer]
}

public struct Review: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let author: String
    public let content: String
    public let createdAt: String?
    public let updatedAt: String?
    public let url: String?
    public let avatarPath: String?
    public let rating: Double?
}

public struct TitleDetailV2: Codable, Sendable {
    public struct ImageGroup: Codable, Sendable {
        public let backdrops: [ImageAsset]
        public let posters: [ImageAsset]
        public let logos: [ImageAsset]
    }

    public let id: Int
    public let mediaType: MediaType
    public let title: String
    public let originalTitle: String
    public let overview: String
    public let posterPath: String?
    public let backdropPath: String?
    public let releaseDate: String?
    public let voteAverage: Double
    public let genreIDs: [Int]
    public let tagline: String
    public let homepage: String?
    public let originalLanguage: String?
    public let originCountries: [String]
    public let adult: Bool
    public let popularity: Double
    public let voteCount: Int
    public let runtimeMinutes: Int?
    public let numberOfSeasons: Int?
    public let status: String?
    public let budget: Int?
    public let revenue: Int?
    public let genres: [Genre]
    public let creators: [Credit]
    public let cast: [Credit]
    public let crew: [Credit]
    public let collection: CollectionSummary?
    public let companies: [OrganizationSummary]
    public let networks: [OrganizationSummary]
    public let seasons: [SeasonSummary]
    public let alternativeTitles: [AlternativeTitle]
    public let externalIDs: [String: String]
    public let images: ImageGroup
    public let videos: [Video]
    public let reviews: PagedResult<Review>
    public let recommendations: PagedResult<TitleSummary>
    public let similar: [TitleSummary]
    public let releaseInformation: [ReleaseInformation]
    public let translations: [TitleTranslation]
    public let watchProviders: [ProviderRegion]

    private enum CodingKeys: String, CodingKey {
        case id, mediaType, title, originalTitle, overview, posterPath, backdropPath, releaseDate, voteAverage
        case genreIDs = "genreIds"
        case tagline, homepage, originalLanguage, originCountries, adult, popularity, voteCount, runtimeMinutes
        case numberOfSeasons, status, budget, revenue, genres, creators, cast, crew, collection, companies, networks, seasons
        case alternativeTitles
        case externalIDs = "externalIds"
        case images, videos, reviews, recommendations, similar, releaseInformation, translations, watchProviders
    }

    public var summary: TitleSummary {
        TitleSummary(
            id: id,
            mediaType: mediaType,
            title: title,
            originalTitle: originalTitle,
            overview: overview,
            posterPath: posterPath,
            backdropPath: backdropPath,
            releaseDate: releaseDate,
            voteAverage: voteAverage,
            genreIDs: genreIDs,
            isAdult: adult
        )
    }

    public var legacy: TitleDetail {
        TitleDetail(
            id: id,
            mediaType: mediaType,
            title: title,
            originalTitle: originalTitle,
            overview: overview,
            posterPath: posterPath,
            backdropPath: backdropPath,
            releaseDate: releaseDate,
            voteAverage: voteAverage,
            genres: genres,
            runtimeMinutes: runtimeMinutes,
            numberOfSeasons: numberOfSeasons,
            status: status,
            cast: cast.compactMap { member in
                guard let id = member.id, let name = member.title else { return nil }
                return CastMember(id: id, name: name, character: member.character, profilePath: member.profilePath)
            },
            videos: videos,
            similar: similar
        )
    }
}

public struct PersonDetail: Codable, Sendable {
    public struct CombinedCredits: Codable, Sendable { public let cast: [Credit]; public let crew: [Credit] }
    public let id: Int
    public let name: String
    public let biography: String
    public let birthday: String?
    public let deathday: String?
    public let placeOfBirth: String?
    public let homepage: String?
    public let profilePath: String?
    public let knownForDepartment: String?
    public let popularity: Double
    public let knownFor: [TitleSummary]
    public let alsoKnownAs: [String]
    public let images: [ImageAsset]
    public let credits: CombinedCredits
    public let externalIDs: [String: String]

    private enum CodingKeys: String, CodingKey {
        case id, name, biography, birthday, deathday, placeOfBirth, homepage, profilePath
        case knownForDepartment, popularity, knownFor, alsoKnownAs, images, credits
        case externalIDs = "externalIds"
    }
}

public struct CollectionDetail: Codable, Sendable {
    public let id: Int
    public let name: String
    public let overview: String
    public let posterPath: String?
    public let backdropPath: String?
    public let parts: [TitleSummary]
    public let images: TitleDetailV2.ImageGroup
}

public struct OrganizationDetail: Codable, Sendable {
    public let entityKind: EntityKind
    public let id: Int
    public let name: String
    public let logoPath: String?
    public let originCountry: String?
    public let description: String
    public let headquarters: String?
    public let homepage: String?
    public let parentCompany: OrganizationSummary?
    public let titles: PagedResult<TitleSummary>
}

public struct KeywordDetail: Codable, Sendable {
    public let id: Int
    public let name: String
    public let titles: PagedResult<TitleSummary>
}

public struct SeasonDetail: Codable, Sendable {
    public let id: Int
    public let seriesId: Int
    public let seasonNumber: Int
    public let name: String
    public let overview: String
    public let posterPath: String?
    public let airDate: String?
    public let episodeCount: Int
    public let episodes: [EpisodeSummary]
    public let credits: PersonDetail.CombinedCredits
    public let images: [ImageAsset]
    public let videos: [Video]
    public let externalIDs: [String: String]

    private enum CodingKeys: String, CodingKey {
        case id, seriesId, seasonNumber, name, overview, posterPath, airDate, episodeCount, episodes, credits, images, videos
        case externalIDs = "externalIds"
    }
}
