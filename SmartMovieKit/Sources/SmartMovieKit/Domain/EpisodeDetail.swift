import Foundation

public struct EpisodeDetail: Codable, Sendable {
    public let id: Int
    public let seriesId: Int
    public let seasonNumber: Int
    public let episodeNumber: Int
    public let name: String
    public let overview: String
    public let stillPath: String?
    public let airDate: String?
    public let runtimeMinutes: Int?
    public let productionCode: String?
    public let voteAverage: Double?
    public let voteCount: Int
    public let crew: [Credit]
    public let guestStars: [Credit]
    public let images: [ImageAsset]
    public let videos: [Video]
    public let externalIDs: [String: String]

    private enum CodingKeys: String, CodingKey {
        case id, seriesId, seasonNumber, episodeNumber, name, overview, stillPath, airDate, runtimeMinutes
        case productionCode, voteAverage, voteCount
        case crew, guestStars, images, videos
        case externalIDs = "externalIds"
    }
}
