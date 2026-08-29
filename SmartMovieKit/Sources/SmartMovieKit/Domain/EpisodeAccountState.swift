import Foundation

public protocol EpisodeAccountStateLoading: Sendable {
    func episodeAccountState(seriesID: Int, season: Int, episode: Int) async throws -> EpisodeAccountState
}

public struct EpisodeAccountState: Codable, Sendable {
    public let seriesId: Int
    public let seasonNumber: Int
    public let episodeNumber: Int
    public let rated: JSONValue

    public var ratingValue: Double? {
        guard case .object(let object) = rated, case .number(let value) = object["value"] else { return nil }
        return value
    }
}
