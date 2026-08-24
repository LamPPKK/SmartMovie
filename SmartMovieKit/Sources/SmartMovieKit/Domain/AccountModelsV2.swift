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
