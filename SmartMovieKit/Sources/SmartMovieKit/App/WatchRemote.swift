import Foundation
import Observation

public enum WatchRemoteAction: String, Sendable {
    case openDetails
    case playTrailer
    case toggleFavorite
    case toggleWatchlist
}

public struct WatchRemoteContext: Sendable {
    public let title: TitleSummary
    public let episode: EpisodeSummary?
    public let artworkURL: URL?
    public let isFavorite: Bool
    public let isWatchlisted: Bool
    public let hasTrailer: Bool

    public init(
        title: TitleSummary,
        episode: EpisodeSummary? = nil,
        artworkURL: URL?,
        isFavorite: Bool,
        isWatchlisted: Bool,
        hasTrailer: Bool
    ) {
        self.title = title
        self.episode = episode
        self.artworkURL = artworkURL
        self.isFavorite = isFavorite
        self.isWatchlisted = isWatchlisted
        self.hasTrailer = hasTrailer
    }

    public var contextKey: String {
        guard let episode else { return title.libraryKey }
        return "episode:\(episode.episodeKey)"
    }

    public var supportsLibraryActions: Bool { episode == nil }
}

@MainActor
public protocol WatchRemoteSession: AnyObject {
    func update(context: WatchRemoteContext)
    func clear(contextKey: String)
}

public extension WatchRemoteSession {
    func clear(contextKey: String) {}
}

public struct WatchRemotePresentation: Identifiable, Sendable {
    public let id = UUID()
    public let title: TitleSummary
    public let episode: EpisodeSummary?
    public let playsTrailer: Bool

    public init(title: TitleSummary, episode: EpisodeSummary? = nil, playsTrailer: Bool) {
        self.title = title
        self.episode = episode
        self.playsTrailer = playsTrailer
    }
}

@MainActor
@Observable
public final class WatchRemoteCoordinator {
    public private(set) var presentation: WatchRemotePresentation?
    public private(set) var libraryRevision = 0

    public init() {}

    public func present(title: TitleSummary, playsTrailer: Bool) {
        presentation = WatchRemotePresentation(title: title, playsTrailer: playsTrailer)
    }

    public func presentEpisode(series: TitleSummary, episode: EpisodeSummary) {
        presentation = WatchRemotePresentation(title: series, episode: episode, playsTrailer: false)
    }

    public func dismissPresentation() {
        presentation = nil
    }

    public func libraryDidChange() {
        libraryRevision += 1
    }
}
