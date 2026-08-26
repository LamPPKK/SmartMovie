import Foundation

public protocol TitleSearching: Sendable {
    func search(
        query: String,
        scope: SearchScope,
        page: Int,
        language: String
    ) async throws -> PagedResult<TitleSummary>
}

public protocol CatalogRepository: TitleSearching, Sendable {
    func home(mediaType: MediaType, language: String) async throws -> HomeFeed
    func genres(mediaType: MediaType, language: String) async throws -> [Genre]
    func discover(
        mediaType: MediaType,
        filter: DiscoverFilter,
        page: Int,
        language: String
    ) async throws -> PagedResult<TitleSummary>
    func discoverBasic(
        mediaType: MediaType,
        filter: DiscoverFilter,
        page: Int,
        language: String
    ) async throws -> PagedResult<TitleSummary>
    func detail(mediaType: MediaType, id: Int, language: String) async throws -> TitleDetail
    func imageConfiguration() async throws -> ImageConfiguration
}

public extension CatalogRepository {
    func discoverBasic(
        mediaType: MediaType,
        filter: DiscoverFilter,
        page: Int,
        language: String
    ) async throws -> PagedResult<TitleSummary> {
        try await discover(mediaType: mediaType, filter: filter, page: page, language: language)
    }
}

public enum LibraryCollection: String, CaseIterable, Identifiable, Sendable {
    case favorites
    case watchlist

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .favorites: String(localized: "Favorites", bundle: .module)
        case .watchlist: String(localized: "Watchlist", bundle: .module)
        }
    }
}

public enum LibrarySort: String, CaseIterable, Identifiable, Sendable {
    case recentlyAdded
    case title
    case releaseDate

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .recentlyAdded: String(localized: "Recently added", bundle: .module)
        case .title: String(localized: "Title", bundle: .module)
        case .releaseDate: String(localized: "Release date", bundle: .module)
        }
    }
}

@MainActor
public protocol LibraryRepository: AnyObject {
    func contains(_ title: TitleSummary, in collection: LibraryCollection) throws -> Bool
    func toggle(_ title: TitleSummary, in collection: LibraryCollection) throws
    func items(
        in collection: LibraryCollection,
        mediaType: MediaType?,
        sort: LibrarySort
    ) throws -> [LibrarySnapshot]
    func reconcileDuplicates() throws
}

@MainActor
public protocol LibrarySyncRepository: LibraryRepository {
    func activateAccount(_ accountID: Int) throws
    func deactivateAccount(removeAccountData: Bool) throws
    func mergeRemote(
        _ remote: [TitleSummary],
        collection: LibraryCollection,
        mediaType: MediaType,
        accountID: Int
    ) throws
    func pendingMutations(limit: Int) throws -> [LibraryPendingMutation]
    func confirmMutation(_ id: UUID) throws
    func failMutation(_ id: UUID, message: String) throws
}
