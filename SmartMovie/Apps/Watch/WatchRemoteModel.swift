import Foundation
import Observation
import WatchKit
@preconcurrency import WatchConnectivity

struct WatchRemoteTitle: Equatable, Sendable {
    let libraryKey: String
    let title: String
    let mediaType: String
    let year: String?
    let artworkURL: URL?
    let rating: Double
    let hasTrailer: Bool
    var isFavorite: Bool
    var isWatchlisted: Bool
}

@MainActor
@Observable
final class WatchRemoteModel: NSObject {
    private enum Action: String {
        case openDetails
        case playTrailer
        case toggleFavorite
        case toggleWatchlist
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

    private let session: WCSession?
    private(set) var currentTitle: WatchRemoteTitle?
    private(set) var isReachable = false
    private(set) var statusMessage: String?

    override init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func playTrailer() {
        send(.playTrailer)
    }

    func openDetails() {
        send(.openDetails)
    }

    func toggleFavorite() {
        send(.toggleFavorite)
    }

    func toggleWatchlist() {
        send(.toggleWatchlist)
    }

    func clearStatus() {
        statusMessage = nil
    }

    private func send(_ action: Action) {
        guard let session, let currentTitle else { return }
        guard session.isReachable else {
            statusMessage = String(localized: "Open SmartMovie on your iPhone to use the remote.")
            WKInterfaceDevice.current().play(.failure)
            return
        }
        let message: [String: Any] = [
            Key.action: action.rawValue,
            Key.libraryKey: currentTitle.libraryKey
        ]
        session.sendMessage(message) { [weak self] reply in
            Task { @MainActor in
                self?.apply(reply: reply)
            }
        } errorHandler: { [weak self] _ in
            Task { @MainActor in
                self?.statusMessage = String(localized: "The iPhone did not receive the command.")
                WKInterfaceDevice.current().play(.failure)
            }
        }
    }

    private func apply(reply: [String: Any]) {
        guard reply[Key.success] as? Bool == true else {
            statusMessage = String(localized: "The iPhone did not receive the command.")
            WKInterfaceDevice.current().play(.failure)
            return
        }
        if let favorite = reply[Key.favorite] as? Bool {
            currentTitle?.isFavorite = favorite
        }
        if let watchlist = reply[Key.watchlist] as? Bool {
            currentTitle?.isWatchlisted = watchlist
        }
        statusMessage = nil
        WKInterfaceDevice.current().play(.success)
    }

    nonisolated private static func decode(context: [String: Any]) -> WatchRemoteTitle? {
        guard
            let libraryKey = context[Key.libraryKey] as? String,
            let title = context[Key.title] as? String,
            let mediaType = context[Key.mediaType] as? String
        else { return nil }

        return WatchRemoteTitle(
            libraryKey: libraryKey,
            title: title,
            mediaType: mediaType,
            year: context[Key.year] as? String,
            artworkURL: (context[Key.artworkURL] as? String).flatMap(URL.init(string:)),
            rating: context[Key.rating] as? Double ?? 0,
            hasTrailer: context[Key.hasTrailer] as? Bool ?? false,
            isFavorite: context[Key.favorite] as? Bool ?? false,
            isWatchlisted: context[Key.watchlist] as? Bool ?? false
        )
    }
}

extension WatchRemoteModel: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        let reachable = activationState == .activated && session.isReachable
        let receivedTitle = Self.decode(context: session.receivedApplicationContext)
        Task { @MainActor [weak self] in
            self?.isReachable = reachable
            if let receivedTitle {
                self?.currentTitle = receivedTitle
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            self?.isReachable = reachable
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let receivedTitle = Self.decode(context: applicationContext)
        Task { @MainActor [weak self] in
            if let receivedTitle {
                self?.currentTitle = receivedTitle
            }
        }
    }
}
