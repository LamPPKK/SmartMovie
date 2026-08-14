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
    public let artworkURL: URL?
    public let isFavorite: Bool
    public let isWatchlisted: Bool
    public let hasTrailer: Bool

    public init(
        title: TitleSummary,
        artworkURL: URL?,
        isFavorite: Bool,
        isWatchlisted: Bool,
        hasTrailer: Bool
    ) {
        self.title = title
        self.artworkURL = artworkURL
        self.isFavorite = isFavorite
        self.isWatchlisted = isWatchlisted
        self.hasTrailer = hasTrailer
    }
}

@MainActor
public protocol WatchRemoteSession: AnyObject {
    func update(context: WatchRemoteContext)
}

public struct WatchRemotePresentation: Identifiable, Sendable {
    public let id = UUID()
    public let title: TitleSummary
    public let playsTrailer: Bool

    public init(title: TitleSummary, playsTrailer: Bool) {
        self.title = title
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

    public func dismissPresentation() {
        presentation = nil
    }

    public func libraryDidChange() {
        libraryRevision += 1
    }
}
