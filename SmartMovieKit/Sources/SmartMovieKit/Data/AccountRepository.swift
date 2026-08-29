import Foundation
import Security

public actor KeychainSessionTokenStore: SessionTokenStore {
    private let service: String
    private let account = "tmdb-session"

    public init(service: String = "app.smartmovie.session") {
        self.service = service
    }

    public func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw APIError.unauthorized
        }
        return token
    }

    public func save(_ token: String) throws {
        guard let data = token.data(using: .utf8) else { throw APIError.invalidResponse }
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw APIError.unauthorized }
        } else if status != errSecSuccess {
            throw APIError.unauthorized
        }
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw APIError.unauthorized }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

public actor MemorySessionTokenStore: SessionTokenStore {
    private var token: String?
    public init(token: String? = nil) { self.token = token }
    public func load() -> String? { token }
    public func save(_ token: String) { self.token = token }
    public func clear() { token = nil }
}

public actor RemoteAccountRepository: AccountRepository {
    private let client: APIClient
    private let tokenStore: any SessionTokenStore

    public init(client: APIClient, tokenStore: any SessionTokenStore = KeychainSessionTokenStore()) {
        self.client = client
        self.tokenStore = tokenStore
    }

    public func createAuthAttempt(returnURI: URL, mode: String) async throws -> AuthAttempt {
        try await client.send(
            "POST",
            path: "v2/auth/attempts",
            body: AuthAttemptRequest(returnURI: returnURI.absoluteString, mode: mode)
        )
    }

    public func authAttempt(id: UUID, deviceCode: String?) async throws -> String {
        var query: [URLQueryItem] = []
        if let deviceCode { query.append(URLQueryItem(name: "device_code", value: deviceCode)) }
        let value: AuthAttemptStatus = try await client.get("v2/auth/attempts/\(id.uuidString.lowercased())", queryItems: query)
        return value.status
    }

    public func completeAuth(id: UUID, deviceCode: String?) async throws -> AuthSession {
        let session: AuthSession = try await client.send(
            "POST",
            path: "v2/auth/complete",
            body: CompleteAuthRequest(attemptID: id, deviceCode: deviceCode)
        )
        if let token = session.sessionToken { try await tokenStore.save(token) }
        return session
    }

    public func profile() async throws -> AccountProfile {
        try await client.get("v2/account/profile", headers: try await authorizationHeaders())
    }

    public func accountState(mediaType: MediaType, id: Int) async throws -> AccountState {
        try await client.get(
            "v2/account/state/\(mediaType.rawValue)/\(id)",
            headers: try await authorizationHeaders()
        )
    }

    public func episodeAccountState(seriesID: Int, season: Int, episode: Int) async throws -> EpisodeAccountState {
        try await client.get(
            "v2/account/state/episode/\(seriesID)/\(season)/\(episode)",
            headers: try await authorizationHeaders()
        )
    }

    public func logout() async throws {
        let _: LogoutResult = try await client.send(
            "POST",
            path: "v2/auth/logout",
            headers: try await authorizationHeaders()
        )
        try await tokenStore.clear()
    }

    public func library(
        _ collection: LibraryCollection,
        mediaType: MediaType,
        page: Int,
        language: String
    ) async throws -> PagedResult<TitleSummary> {
        try await client.get(
            "v2/account/\(collection.rawValue)/\(mediaType.rawValue)",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "language", value: language),
                URLQueryItem(name: "sort_by", value: "created_at.desc")
            ],
            headers: try await authorizationHeaders()
        )
    }

    public func setLibrary(
        _ collection: LibraryCollection,
        mediaType: MediaType,
        mediaID: Int,
        enabled: Bool,
        mutationID: UUID
    ) async throws -> MutationResult {
        try await client.send(
            "PUT",
            path: "v2/account/\(collection.rawValue)/\(mediaType.rawValue)",
            body: LibraryMutation(mediaID: mediaID, enabled: enabled, mutationID: mutationID),
            headers: try await mutationHeaders(mutationID),
            retrySafe: true
        )
    }

    public func setRating(mediaType: MediaType, id: Int, value: Double?, mutationID: UUID) async throws -> MutationResult {
        if let value {
            return try await client.send(
                "PUT",
                path: "v2/account/ratings/\(mediaType.rawValue)/\(id)",
                body: RatingMutation(value: value, mutationID: mutationID),
                headers: try await mutationHeaders(mutationID),
                retrySafe: true
            )
        }
        return try await client.send(
            "DELETE",
            path: "v2/account/ratings/\(mediaType.rawValue)/\(id)",
            headers: try await mutationHeaders(mutationID),
            retrySafe: true
        )
    }

    public func setEpisodeRating(
        seriesID: Int,
        season: Int,
        episode: Int,
        value: Double?,
        mutationID: UUID
    ) async throws -> MutationResult {
        let path = "v2/account/ratings/episode/\(seriesID)/\(season)/\(episode)"
        if let value {
            return try await client.send(
                "PUT",
                path: path,
                body: RatingMutation(value: value, mutationID: mutationID),
                headers: try await mutationHeaders(mutationID),
                retrySafe: true
            )
        }
        return try await client.send(
            "DELETE",
            path: path,
            headers: try await mutationHeaders(mutationID),
            retrySafe: true
        )
    }

    public func recommendations(mediaType: MediaType, page: Int, language: String) async throws -> PagedResult<TitleSummary> {
        try await client.get(
            "v2/account/recommendations/\(mediaType.rawValue)",
            queryItems: [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "language", value: language)],
            headers: try await authorizationHeaders()
        )
    }

    public func lists(page: Int) async throws -> PagedResult<UserList> {
        try await client.get(
            "v2/account/lists",
            queryItems: [URLQueryItem(name: "page", value: String(page))],
            headers: try await authorizationHeaders()
        )
    }

    public func list(id: Int, page: Int, language: String) async throws -> UserList {
        try await client.get(
            "v2/account/lists/\(id)",
            queryItems: [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "language", value: language)],
            headers: try await authorizationHeaders()
        )
    }

    public func createList(
        _ metadata: UserListMetadataMutation,
        mutationID: UUID
    ) async throws -> MutationResult {
        try await client.send(
            "POST",
            path: "v2/account/lists",
            body: ListMetadata(
                name: metadata.name,
                description: metadata.description,
                isPublic: metadata.isPublic,
                region: metadata.region,
                language: metadata.language,
                mutationID: mutationID
            ),
            headers: try await mutationHeaders(mutationID),
            retrySafe: true
        )
    }

    public func updateList(
        id: Int,
        name: String,
        description: String,
        isPublic: Bool,
        mutationID: UUID
    ) async throws -> MutationResult {
        try await client.send(
            "PUT",
            path: "v2/account/lists/\(id)",
            body: ListMetadata(
                name: name,
                description: description,
                isPublic: isPublic,
                region: nil,
                language: nil,
                mutationID: mutationID
            ),
            headers: try await mutationHeaders(mutationID),
            retrySafe: true
        )
    }

    public func deleteList(id: Int, mutationID: UUID) async throws -> MutationResult {
        try await client.send(
            "DELETE",
            path: "v2/account/lists/\(id)",
            headers: try await mutationHeaders(mutationID),
            retrySafe: true
        )
    }

    public func mutateListItems(
        id: Int,
        items: [UserListItemMutation],
        remove: Bool,
        mutationID: UUID
    ) async throws -> MutationResult {
        try await client.send(
            remove ? "DELETE" : "POST",
            path: "v2/account/lists/\(id)/items",
            body: ListItemsMutation(items: items, mutationID: mutationID),
            headers: try await mutationHeaders(mutationID),
            retrySafe: true
        )
    }

    private func authorizationHeaders() async throws -> [String: String] {
        guard let token = try await tokenStore.load() else { throw APIError.unauthorized }
        return ["Authorization": "Bearer \(token)"]
    }

    private func mutationHeaders(_ mutationID: UUID) async throws -> [String: String] {
        var headers = try await authorizationHeaders()
        headers["Idempotency-Key"] = mutationID.uuidString.lowercased()
        return headers
    }
}

private struct AuthAttemptRequest: Encodable, Sendable {
    let returnURI: String
    let mode: String

    private enum CodingKeys: String, CodingKey { case returnURI = "returnUri"; case mode }
}

private struct CompleteAuthRequest: Encodable, Sendable {
    let attemptID: UUID
    let deviceCode: String?

    private enum CodingKeys: String, CodingKey { case attemptID = "attemptId"; case deviceCode }
}

private struct AuthAttemptStatus: Decodable, Sendable { let status: String }
private struct LogoutResult: Decodable, Sendable { let success: Bool }

private struct LibraryMutation: Encodable, Sendable {
    let mediaID: Int
    let enabled: Bool
    let mutationID: UUID

    private enum CodingKeys: String, CodingKey { case mediaID = "mediaId"; case enabled; case mutationID = "mutationId" }
}

private struct RatingMutation: Encodable, Sendable {
    let value: Double
    let mutationID: UUID

    private enum CodingKeys: String, CodingKey { case value; case mutationID = "mutationId" }
}

private struct ListMetadata: Encodable, Sendable {
    let name: String
    let description: String
    let isPublic: Bool
    let region: String?
    let language: String?
    let mutationID: UUID

    private enum CodingKeys: String, CodingKey {
        case name, description
        case isPublic = "public"
        case region = "iso_3166_1"
        case language = "iso_639_1"
        case mutationID = "mutationId"
    }
}

private struct ListItemsMutation: Encodable, Sendable {
    let items: [UserListItemMutation]
    let mutationID: UUID

    private enum CodingKeys: String, CodingKey { case items; case mutationID = "mutationId" }
}
