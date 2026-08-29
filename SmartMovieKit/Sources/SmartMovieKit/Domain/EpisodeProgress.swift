import Foundation

public struct EpisodeWatchKey: Hashable, Sendable {
    public let seriesID: Int
    public let seasonNumber: Int
    public let episodeNumber: Int

    public init(seriesID: Int, seasonNumber: Int, episodeNumber: Int) {
        self.seriesID = seriesID
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
    }

    public var rawValue: String { "\(seriesID):\(seasonNumber):\(episodeNumber)" }
}

@MainActor
public protocol EpisodeProgressRepository: AnyObject {
    func isWatched(_ key: EpisodeWatchKey) throws -> Bool
    func watchedEpisodeNumbers(seriesID: Int, seasonNumber: Int) throws -> Set<Int>
    func setWatched(_ watched: Bool, for key: EpisodeWatchKey) throws
    func setSeasonWatched(_ watched: Bool, seriesID: Int, seasonNumber: Int, episodeNumbers: [Int]) throws
    func reconcileDuplicates() throws
}

public enum EpisodeProgressError: LocalizedError {
    case unavailable

    public var errorDescription: String? {
        String(localized: "Episode progress is unavailable.", bundle: .module)
    }
}

@MainActor
public final class UnavailableEpisodeProgressRepository: EpisodeProgressRepository {
    public init() {}
    public func isWatched(_ key: EpisodeWatchKey) throws -> Bool { false }
    public func watchedEpisodeNumbers(seriesID: Int, seasonNumber: Int) throws -> Set<Int> { [] }
    public func setWatched(_ watched: Bool, for key: EpisodeWatchKey) throws { throw EpisodeProgressError.unavailable }
    public func setSeasonWatched(
        _ watched: Bool, seriesID: Int, seasonNumber: Int, episodeNumbers: [Int]
    ) throws { throw EpisodeProgressError.unavailable }
    public func reconcileDuplicates() throws {}
}
