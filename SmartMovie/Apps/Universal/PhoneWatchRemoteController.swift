#if os(iOS) && !targetEnvironment(macCatalyst)
import Foundation
import SmartMovieKit
@preconcurrency import WatchConnectivity

@MainActor
final class PhoneWatchRemoteController: NSObject, WatchRemoteSession {
    private struct ReplyHandler: @unchecked Sendable {
        let call: ([String: Any]) -> Void
    }

    private struct RemoteCommand: Sendable {
        let action: WatchRemoteAction
        let libraryKey: String
        let contextKey: String?
    }

    private enum Key {
        static let action = "action"
        static let artworkURL = "artworkURL"
        static let cleared = "cleared"
        static let contextKey = "contextKey"
        static let contextKind = "contextKind"
        static let episodeNumber = "episodeNumber"
        static let favorite = "favorite"
        static let hasTrailer = "hasTrailer"
        static let libraryKey = "libraryKey"
        static let libraryActionsAvailable = "libraryActionsAvailable"
        static let mediaType = "mediaType"
        static let seasonNumber = "seasonNumber"
        static let seriesTitle = "seriesTitle"
        static let success = "ok"
        static let rating = "rating"
        static let title = "title"
        static let watchlist = "watchlist"
        static let year = "year"
    }

    private let library: any LibraryRepository
    private let coordinator: WatchRemoteCoordinator
    private let session: WCSession?
    private var currentContext: WatchRemoteContext?

    init(library: any LibraryRepository, coordinator: WatchRemoteCoordinator) {
        self.library = library
        self.coordinator = coordinator
        session = WCSession.isSupported() ? .default : nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func update(context: WatchRemoteContext) {
        currentContext = context
        publishCurrentContext()
    }

    func clear(contextKey: String) {
        guard currentContext?.contextKey == contextKey else { return }
        currentContext = nil
        publishCurrentContext()
    }

    private func publishCurrentContext() {
        guard let session, session.activationState == .activated else { return }
        let applicationContext = currentContext.map { payload(for: $0) } ?? [Key.cleared: true]
        do {
            try session.updateApplicationContext(applicationContext)
        } catch {
            // The next detail update or activation callback retries with fresh state.
        }
    }

    private func payload(for context: WatchRemoteContext) -> [String: Any] {
        let episode = context.episode
        var payload: [String: Any] = [
            Key.contextKey: context.contextKey,
            Key.contextKind: episode == nil ? "title" : "episode",
            Key.favorite: context.supportsLibraryActions && context.isFavorite,
            Key.hasTrailer: episode == nil && context.hasTrailer,
            Key.libraryKey: context.title.libraryKey,
            Key.libraryActionsAvailable: context.supportsLibraryActions,
            Key.mediaType: episode == nil ? context.title.mediaType.rawValue : "episode",
            Key.rating: episode?.voteAverage ?? context.title.voteAverage,
            Key.title: episode?.name ?? context.title.displayTitle,
            Key.watchlist: context.supportsLibraryActions && context.isWatchlisted
        ]
        if let artworkURL = context.artworkURL?.absoluteString {
            payload[Key.artworkURL] = artworkURL
        }
        if let episode {
            payload[Key.episodeNumber] = episode.episodeNumber
            payload[Key.seasonNumber] = episode.seasonNumber
            payload[Key.seriesTitle] = context.title.displayTitle
        }
        let year = episode?.airDate.map { String($0.prefix(4)) } ?? context.title.releaseYear
        if let year {
            payload[Key.year] = year
        }
        return payload
    }

    private func handle(command: RemoteCommand?) -> [String: Any] {
        guard
            let command,
            let context = currentContext,
            command.contextKey == context.contextKey || (
                command.contextKey == nil && command.libraryKey == context.title.libraryKey
            )
        else {
            return [Key.success: false]
        }

        switch command.action {
        case .openDetails:
            if let episode = context.episode {
                coordinator.presentEpisode(series: context.title, episode: episode)
            } else {
                coordinator.present(title: context.title, playsTrailer: false)
            }
        case .playTrailer:
            guard context.episode == nil, context.hasTrailer else { return [Key.success: false] }
            coordinator.present(title: context.title, playsTrailer: true)
        case .toggleFavorite:
            guard context.supportsLibraryActions else { return [Key.success: false] }
            guard toggle(.favorites, context: context) else { return [Key.success: false] }
        case .toggleWatchlist:
            guard context.supportsLibraryActions else { return [Key.success: false] }
            guard toggle(.watchlist, context: context) else { return [Key.success: false] }
        }
        return replyPayload()
    }

    private func toggle(_ collection: LibraryCollection, context: WatchRemoteContext) -> Bool {
        do {
            try library.toggle(context.title, in: collection)
            let refreshedContext = WatchRemoteContext(
                title: context.title,
                episode: context.episode,
                artworkURL: context.artworkURL,
                isFavorite: try library.contains(context.title, in: .favorites),
                isWatchlisted: try library.contains(context.title, in: .watchlist),
                hasTrailer: context.hasTrailer
            )
            currentContext = refreshedContext
            coordinator.libraryDidChange()
            publishCurrentContext()
            return true
        } catch {
            return false
        }
    }

    private func replyPayload() -> [String: Any] {
        guard let currentContext else { return [Key.success: false] }
        return [
            Key.favorite: currentContext.isFavorite,
            Key.success: true,
            Key.watchlist: currentContext.isWatchlisted
        ]
    }
}

extension PhoneWatchRemoteController: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        guard activationState == .activated, error == nil else { return }
        Task { @MainActor [weak self] in
            self?.publishCurrentContext()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let command = Self.decodeCommand(message)
        let safeReplyHandler = ReplyHandler(call: replyHandler)
        Task { @MainActor [weak self] in
            safeReplyHandler.call(self?.handle(command: command) ?? [Key.success: false])
        }
    }

    nonisolated private static func decodeCommand(_ message: [String: Any]) -> RemoteCommand? {
        guard
            let rawAction = message[Key.action] as? String,
            let action = WatchRemoteAction(rawValue: rawAction),
            let libraryKey = message[Key.libraryKey] as? String
        else { return nil }
        return RemoteCommand(
            action: action,
            libraryKey: libraryKey,
            contextKey: message[Key.contextKey] as? String
        )
    }
}
#endif
