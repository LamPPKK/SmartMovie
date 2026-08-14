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
    }

    private enum Key {
        static let action = "action"
        static let artworkURL = "artworkURL"
        static let favorite = "favorite"
        static let hasTrailer = "hasTrailer"
        static let libraryKey = "libraryKey"
        static let mediaType = "mediaType"
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

    private func publishCurrentContext() {
        guard let session, session.activationState == .activated, let currentContext else { return }
        do {
            try session.updateApplicationContext(payload(for: currentContext))
        } catch {
            // The next detail update or activation callback retries with fresh state.
        }
    }

    private func payload(for context: WatchRemoteContext) -> [String: Any] {
        var payload: [String: Any] = [
            Key.favorite: context.isFavorite,
            Key.hasTrailer: context.hasTrailer,
            Key.libraryKey: context.title.libraryKey,
            Key.mediaType: context.title.mediaType.rawValue,
            Key.rating: context.title.voteAverage,
            Key.title: context.title.displayTitle,
            Key.watchlist: context.isWatchlisted
        ]
        if let artworkURL = context.artworkURL?.absoluteString {
            payload[Key.artworkURL] = artworkURL
        }
        if let year = context.title.releaseYear {
            payload[Key.year] = year
        }
        return payload
    }

    private func handle(command: RemoteCommand?) -> [String: Any] {
        guard
            let command,
            let context = currentContext,
            command.libraryKey == context.title.libraryKey
        else {
            return [Key.success: false]
        }

        switch command.action {
        case .openDetails:
            coordinator.present(title: context.title, playsTrailer: false)
        case .playTrailer:
            coordinator.present(title: context.title, playsTrailer: true)
        case .toggleFavorite:
            guard toggle(.favorites, context: context) else { return [Key.success: false] }
        case .toggleWatchlist:
            guard toggle(.watchlist, context: context) else { return [Key.success: false] }
        }
        return replyPayload()
    }

    private func toggle(_ collection: LibraryCollection, context: WatchRemoteContext) -> Bool {
        do {
            try library.toggle(context.title, in: collection)
            let refreshedContext = WatchRemoteContext(
                title: context.title,
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
        return RemoteCommand(action: action, libraryKey: libraryKey)
    }
}
#endif
