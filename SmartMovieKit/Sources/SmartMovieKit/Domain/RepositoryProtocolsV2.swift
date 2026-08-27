import Foundation

public protocol CatalogV2Repository: Sendable {
    func capabilities() async throws -> CapabilitiesV2
    func discoverConfiguration(language: String, region: String?) async throws -> DiscoverConfiguration
    func trending(
        kind: String,
        window: String,
        page: Int,
        language: String,
        includeAdult: Bool
    ) async throws -> PagedResult<CatalogEntity>
    func searchEntities(_ request: EntitySearchRequest) async throws -> PagedResult<CatalogEntity>
    func findExternalID(
        _ externalID: String,
        source: ExternalIDSource,
        language: String,
        includeAdult: Bool
    ) async throws -> ExternalIDFindResult
    func deepDetail(
        mediaType: MediaType,
        id: Int,
        language: String,
        region: String?,
        includeAdult: Bool
    ) async throws -> TitleDetailV2
    func person(id: Int, language: String, includeAdult: Bool) async throws -> PersonDetail
    func collection(id: Int, language: String, includeAdult: Bool) async throws -> CollectionDetail
    func organization(
        kind: EntityKind,
        id: Int,
        language: String,
        page: Int,
        includeAdult: Bool
    ) async throws -> OrganizationDetail
    func keyword(id: Int, language: String, page: Int, includeAdult: Bool) async throws -> KeywordDetail
    func season(seriesID: Int, number: Int, language: String) async throws -> SeasonDetail
    func episode(seriesID: Int, season: Int, number: Int, language: String) async throws -> EpisodeDetail
    func credit(id: String, language: String, includeAdult: Bool) async throws -> CreditDetail
}

public protocol AccountRecommendationsLoading: Sendable {
    func recommendations(
        mediaType: MediaType,
        page: Int,
        language: String
    ) async throws -> PagedResult<TitleSummary>
}

public protocol AccountListLoading: Sendable {
    func list(id: Int, page: Int, language: String) async throws -> UserList
}

public protocol AccountRepository: AccountRecommendationsLoading, AccountListLoading, Sendable {
    func createAuthAttempt(returnURI: URL, mode: String) async throws -> AuthAttempt
    func authAttempt(id: UUID, deviceCode: String?) async throws -> String
    func completeAuth(id: UUID, deviceCode: String?) async throws -> AuthSession
    func profile() async throws -> AccountProfile
    func accountState(mediaType: MediaType, id: Int) async throws -> AccountState
    func logout() async throws
    func library(
        _ collection: LibraryCollection,
        mediaType: MediaType,
        page: Int,
        language: String
    ) async throws -> PagedResult<TitleSummary>
    func setLibrary(
        _ collection: LibraryCollection,
        mediaType: MediaType,
        mediaID: Int,
        enabled: Bool,
        mutationID: UUID
    ) async throws -> MutationResult
    func setRating(mediaType: MediaType, id: Int, value: Double?, mutationID: UUID) async throws -> MutationResult
    func setEpisodeRating(seriesID: Int, season: Int, episode: Int, value: Double?, mutationID: UUID) async throws -> MutationResult
    func recommendations(mediaType: MediaType, page: Int, language: String) async throws -> PagedResult<TitleSummary>
    func lists(page: Int) async throws -> PagedResult<UserList>
    func list(id: Int, page: Int, language: String) async throws -> UserList
    func createList(_ metadata: UserListMetadataMutation, mutationID: UUID) async throws -> MutationResult
    func updateList(id: Int, name: String, description: String, isPublic: Bool, mutationID: UUID) async throws -> MutationResult
    func deleteList(id: Int, mutationID: UUID) async throws -> MutationResult
    func mutateListItems(id: Int, items: [UserListItemMutation], remove: Bool, mutationID: UUID) async throws -> MutationResult
}

public struct UserListItemMutation: Codable, Hashable, Sendable {
    public let mediaType: MediaType
    public let mediaId: Int
    public let comment: String?

    public init(mediaType: MediaType, mediaId: Int, comment: String? = nil) {
        self.mediaType = mediaType
        self.mediaId = mediaId
        self.comment = comment
    }
}

public struct EntitySearchRequest: Hashable, Sendable {
    public let query: String
    public let scope: SearchScopeV2
    public let page: Int
    public let language: String
    public let region: String?
    public let includeAdult: Bool

    public init(query: String, scope: SearchScopeV2, context: CatalogPageContext) {
        self.query = query
        self.scope = scope
        page = context.page
        language = context.language
        region = context.region
        includeAdult = context.includeAdult
    }
}

public struct CatalogPageContext: Hashable, Sendable {
    public let page: Int
    public let language: String
    public let region: String?
    public let includeAdult: Bool

    public init(page: Int, language: String, region: String?, includeAdult: Bool) {
        self.page = page
        self.language = language
        self.region = region
        self.includeAdult = includeAdult
    }
}

public struct UserListMetadataMutation: Codable, Hashable, Sendable {
    public let name: String
    public let description: String
    public let isPublic: Bool
    public let region: String
    public let language: String

    public init(name: String, description: String, isPublic: Bool, region: String, language: String) {
        self.name = name
        self.description = description
        self.isPublic = isPublic
        self.region = region
        self.language = language
    }
}

public struct MutationResult: Codable, Sendable {
    public let mutationId: UUID
    public let success: Bool?
    public let statusCode: Int?
    public let statusMessage: String?
    public let listId: Int?

    public init(
        mutationId: UUID,
        success: Bool? = nil,
        statusCode: Int? = nil,
        statusMessage: String? = nil,
        listId: Int? = nil
    ) {
        self.mutationId = mutationId
        self.success = success
        self.statusCode = statusCode
        self.statusMessage = statusMessage
        self.listId = listId
    }
}

public actor UnavailableAccountRepository: AccountRepository {
    public init() {}
    public func createAuthAttempt(returnURI: URL, mode: String) async throws -> AuthAttempt { throw APIError.unauthorized }
    public func authAttempt(id: UUID, deviceCode: String?) async throws -> String { throw APIError.unauthorized }
    public func completeAuth(id: UUID, deviceCode: String?) async throws -> AuthSession { throw APIError.unauthorized }
    public func profile() async throws -> AccountProfile { throw APIError.unauthorized }
    public func accountState(mediaType: MediaType, id: Int) async throws -> AccountState { throw APIError.unauthorized }
    public func logout() async throws { throw APIError.unauthorized }
    public func library(
        _ collection: LibraryCollection,
        mediaType: MediaType,
        page: Int,
        language: String
    ) async throws -> PagedResult<TitleSummary> { throw APIError.unauthorized }
    public func setLibrary(
        _ collection: LibraryCollection,
        mediaType: MediaType,
        mediaID: Int,
        enabled: Bool,
        mutationID: UUID
    ) async throws -> MutationResult { throw APIError.unauthorized }
    public func setRating(mediaType: MediaType, id: Int, value: Double?, mutationID: UUID) async throws -> MutationResult {
        throw APIError.unauthorized
    }
    public func setEpisodeRating(
        seriesID: Int,
        season: Int,
        episode: Int,
        value: Double?,
        mutationID: UUID
    ) async throws -> MutationResult { throw APIError.unauthorized }
    public func recommendations(
        mediaType: MediaType,
        page: Int,
        language: String
    ) async throws -> PagedResult<TitleSummary> { throw APIError.unauthorized }
    public func lists(page: Int) async throws -> PagedResult<UserList> { throw APIError.unauthorized }
    public func list(id: Int, page: Int, language: String) async throws -> UserList { throw APIError.unauthorized }
    public func createList(
        _ metadata: UserListMetadataMutation,
        mutationID: UUID
    ) async throws -> MutationResult { throw APIError.unauthorized }
    public func updateList(
        id: Int,
        name: String,
        description: String,
        isPublic: Bool,
        mutationID: UUID
    ) async throws -> MutationResult { throw APIError.unauthorized }
    public func deleteList(id: Int, mutationID: UUID) async throws -> MutationResult { throw APIError.unauthorized }
    public func mutateListItems(
        id: Int,
        items: [UserListItemMutation],
        remove: Bool,
        mutationID: UUID
    ) async throws -> MutationResult { throw APIError.unauthorized }
}

public protocol SessionTokenStore: Sendable {
    func load() async throws -> String?
    func save(_ token: String) async throws
    func clear() async throws
}
