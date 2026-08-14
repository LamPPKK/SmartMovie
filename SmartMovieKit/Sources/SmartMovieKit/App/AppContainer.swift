import Foundation
import Observation

@MainActor
@Observable
public final class AppContainer {
    public let catalog: any CatalogRepository
    public let library: any LibraryRepository
    public let watchRemoteSession: (any WatchRemoteSession)?
    public let watchRemoteCoordinator: WatchRemoteCoordinator
    public private(set) var imageConfiguration = ImageConfiguration(
        secureBaseURL: "https://image.tmdb.org/t/p/",
        posterSizes: ["w342", "w500", "original"],
        backdropSizes: ["w780", "w1280", "original"],
        profileSizes: ["w185", "h632", "original"]
    )

    public init(
        catalog: any CatalogRepository,
        library: any LibraryRepository,
        watchRemoteSession: (any WatchRemoteSession)? = nil,
        watchRemoteCoordinator: WatchRemoteCoordinator = WatchRemoteCoordinator()
    ) {
        self.catalog = catalog
        self.library = library
        self.watchRemoteSession = watchRemoteSession
        self.watchRemoteCoordinator = watchRemoteCoordinator
    }

    public func prepare() async {
        do {
            try library.reconcileDuplicates()
            imageConfiguration = try await catalog.imageConfiguration()
        } catch {
            // Feature screens surface network failures. A bundled image configuration
            // remains available so a configuration outage does not blank the UI.
        }
    }

    public func imageURL(path: String?, kind: ImageKind) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        let size: String = switch kind {
        case .poster: preferredSize(imageConfiguration.posterSizes, candidates: ["w500", "w342"])
        case .backdrop: preferredSize(imageConfiguration.backdropSizes, candidates: ["w1280", "w780"])
        case .profile: preferredSize(imageConfiguration.profileSizes, candidates: ["w185", "h632"])
        }
        let base = imageConfiguration.secureBaseURL.hasSuffix("/")
            ? imageConfiguration.secureBaseURL
            : imageConfiguration.secureBaseURL + "/"
        return URL(string: base + size + "/" + normalizedPath(path))
    }

    private func preferredSize(_ available: [String], candidates: [String]) -> String {
        candidates.first(where: available.contains) ?? available.first ?? "original"
    }

    private func normalizedPath(_ path: String) -> String {
        path.hasPrefix("/") ? String(path.dropFirst()) : path
    }
}

public enum ImageKind: Sendable {
    case poster
    case backdrop
    case profile
}

public enum Loadable<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)

    public var isLoading: Bool {
        if case .loading = self { true } else { false }
    }
}
