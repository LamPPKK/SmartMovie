import Foundation

public struct UserList: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let description: String
    public let `public`: Bool
    public let page: Int?
    public let totalPages: Int?
    public let results: [TitleSummary]

    public init(
        id: Int,
        name: String,
        description: String,
        isPublic: Bool,
        page: Int? = nil,
        totalPages: Int? = nil,
        results: [TitleSummary]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.public = isPublic
        self.page = page
        self.totalPages = totalPages
        self.results = results
    }
}

public struct AccountProfile: Codable, Hashable, Sendable {
    public let id: Int
    public let username: String
    public let name: String
    public let language: String?
    public let country: String?
    public let includeAdult: Bool
    public let avatarPath: String?
    public let gravatarHash: String?
}

public struct AccountState: Codable, Sendable {
    public let mediaType: MediaType
    public let mediaId: Int
    public let favorite: Bool
    public let watchlist: Bool
    public let rated: JSONValue
}

public struct AuthAttempt: Codable, Hashable, Sendable {
    public let attemptId: UUID
    public let status: String
    public let authorizationUrl: URL
    public let deviceCode: String?
    public let expiresAt: Date
    public let pollingInterval: Int?
}

public struct AuthSession: Codable, Sendable {
    public let sessionToken: String?
    public let csrfToken: String
    public let expiresAt: Date
    public let profile: AccountProfile
}
