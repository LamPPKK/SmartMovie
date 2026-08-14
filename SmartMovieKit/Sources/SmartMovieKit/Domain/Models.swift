import Foundation

public enum MediaType: String, Codable, CaseIterable, Identifiable, Sendable {
    case movie
    case tv

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .movie: String(localized: "Movies", bundle: .module)
        case .tv: String(localized: "TV Series", bundle: .module)
        }
    }

    public var releaseDateLabel: String {
        switch self {
        case .movie: String(localized: "Release date", bundle: .module)
        case .tv: String(localized: "First air date", bundle: .module)
        }
    }
}

public struct Genre: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

public struct CastMember: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let character: String?
    public let profilePath: String?

    public init(id: Int, name: String, character: String? = nil, profilePath: String? = nil) {
        self.id = id
        self.name = name
        self.character = character
        self.profilePath = profilePath
    }
}

public struct Video: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let key: String
    public let name: String
    public let site: String
    public let type: String
    public let official: Bool
    public let language: String?

    public init(
        id: String,
        key: String,
        name: String,
        site: String,
        type: String,
        official: Bool,
        language: String? = nil
    ) {
        self.id = id
        self.key = key
        self.name = name
        self.site = site
        self.type = type
        self.official = official
        self.language = language
    }
}

public struct TitleSummary: Codable, Hashable, Identifiable, Sendable {
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

    private enum CodingKeys: String, CodingKey {
        case id
        case mediaType
        case title
        case originalTitle
        case overview
        case posterPath
        case backdropPath
        case releaseDate
        case voteAverage
        // JSONDecoder converts `genre_ids` to `genreIds`, not `genreIDs`.
        case genreIDs = "genreIds"
    }

    public init(
        id: Int,
        mediaType: MediaType,
        title: String,
        originalTitle: String,
        overview: String,
        posterPath: String? = nil,
        backdropPath: String? = nil,
        releaseDate: String? = nil,
        voteAverage: Double = 0,
        genreIDs: [Int] = []
    ) {
        self.id = id
        self.mediaType = mediaType
        self.title = title
        self.originalTitle = originalTitle
        self.overview = overview
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.releaseDate = releaseDate
        self.voteAverage = voteAverage
        self.genreIDs = genreIDs
    }

    public var libraryKey: String { "\(mediaType.rawValue):\(id)" }
    public var displayTitle: String { title.isEmpty ? originalTitle : title }
    public var releaseYear: String? { releaseDate?.prefix(4).description }
}

public struct TitleDetail: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let mediaType: MediaType
    public let title: String
    public let originalTitle: String
    public let overview: String
    public let posterPath: String?
    public let backdropPath: String?
    public let releaseDate: String?
    public let voteAverage: Double
    public let genres: [Genre]
    public let runtimeMinutes: Int?
    public let numberOfSeasons: Int?
    public let status: String?
    public let cast: [CastMember]
    public let videos: [Video]
    public let similar: [TitleSummary]

    public init(
        id: Int,
        mediaType: MediaType,
        title: String,
        originalTitle: String,
        overview: String,
        posterPath: String? = nil,
        backdropPath: String? = nil,
        releaseDate: String? = nil,
        voteAverage: Double = 0,
        genres: [Genre] = [],
        runtimeMinutes: Int? = nil,
        numberOfSeasons: Int? = nil,
        status: String? = nil,
        cast: [CastMember] = [],
        videos: [Video] = [],
        similar: [TitleSummary] = []
    ) {
        self.id = id
        self.mediaType = mediaType
        self.title = title
        self.originalTitle = originalTitle
        self.overview = overview
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.releaseDate = releaseDate
        self.voteAverage = voteAverage
        self.genres = genres
        self.runtimeMinutes = runtimeMinutes
        self.numberOfSeasons = numberOfSeasons
        self.status = status
        self.cast = cast
        self.videos = videos
        self.similar = similar
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
            genreIDs: genres.map(\.id)
        )
    }
}

public struct PagedResult<Element: Codable & Sendable>: Codable, Sendable {
    public let page: Int
    public let totalPages: Int
    public let results: [Element]

    public init(page: Int, totalPages: Int, results: [Element]) {
        self.page = page
        self.totalPages = totalPages
        self.results = results
    }
}

public struct HomeSection: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let items: [TitleSummary]

    public init(id: String, title: String, items: [TitleSummary]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

public struct HomeFeed: Codable, Sendable {
    public let mediaType: MediaType
    public let hero: TitleSummary?
    public let sections: [HomeSection]

    public init(mediaType: MediaType, hero: TitleSummary?, sections: [HomeSection]) {
        self.mediaType = mediaType
        self.hero = hero
        self.sections = sections
    }
}

public enum SearchScope: String, CaseIterable, Identifiable, Sendable {
    case all
    case movie
    case tv

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all: String(localized: "All", bundle: .module)
        case .movie: String(localized: "Movies", bundle: .module)
        case .tv: String(localized: "TV Series", bundle: .module)
        }
    }
}

public enum DiscoverSort: String, CaseIterable, Identifiable, Sendable {
    case popularity = "popularity.desc"
    case rating = "vote_average.desc"
    case releaseDate = "primary_release_date.desc"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .popularity: String(localized: "Popularity", bundle: .module)
        case .rating: String(localized: "Rating", bundle: .module)
        case .releaseDate: String(localized: "Release date", bundle: .module)
        }
    }
}

public struct DiscoverFilter: Equatable, Sendable {
    public var genres: Set<Int>
    public var year: Int?
    public var minimumRating: Double
    public var sort: DiscoverSort

    public init(
        genres: Set<Int> = [],
        year: Int? = nil,
        minimumRating: Double = 0,
        sort: DiscoverSort = .popularity
    ) {
        self.genres = genres
        self.year = year
        self.minimumRating = minimumRating
        self.sort = sort
    }
}

public struct ImageConfiguration: Codable, Sendable {
    public let secureBaseURL: String
    public let posterSizes: [String]
    public let backdropSizes: [String]
    public let profileSizes: [String]

    private enum CodingKeys: String, CodingKey {
        // JSONDecoder converts `secure_base_url` to `secureBaseUrl`.
        case secureBaseURL = "secureBaseUrl"
        case posterSizes
        case backdropSizes
        case profileSizes
    }

    public init(
        secureBaseURL: String,
        posterSizes: [String],
        backdropSizes: [String],
        profileSizes: [String]
    ) {
        self.secureBaseURL = secureBaseURL
        self.posterSizes = posterSizes
        self.backdropSizes = backdropSizes
        self.profileSizes = profileSizes
    }
}
