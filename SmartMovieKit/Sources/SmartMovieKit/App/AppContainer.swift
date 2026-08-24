import Foundation
import Observation

@MainActor
@Observable
public final class AppContainer {
    public let catalog: any CatalogRepository
    public let library: any LibraryRepository
    public let account: any AccountRepository
    public let accountSession: AccountSessionController
    public let accountMutations: AccountMutationCoordinator
    public let adultContent: AdultContentController
    public let regionSettings: RegionSettings
    public let watchRemoteSession: (any WatchRemoteSession)?
    public let watchRemoteCoordinator: WatchRemoteCoordinator
    public private(set) var imageConfiguration = ImageConfiguration(
        secureBaseURL: "https://image.tmdb.org/t/p/",
        posterSizes: ["w342", "w500", "original"],
        backdropSizes: ["w780", "w1280", "original"],
        profileSizes: ["w185", "h632", "original"]
    )
    public private(set) var capabilities: CapabilitiesV2?

    public init(
        catalog: any CatalogRepository,
        library: any LibraryRepository,
        account: any AccountRepository = UnavailableAccountRepository(),
        accountMutationStore: any AccountMutationStoring = FileAccountMutationStore(),
        watchRemoteSession: (any WatchRemoteSession)? = nil,
        watchRemoteCoordinator: WatchRemoteCoordinator = WatchRemoteCoordinator()
    ) {
        self.catalog = catalog
        self.library = library
        self.account = account
        accountSession = AccountSessionController(account: account)
        accountMutations = AccountMutationCoordinator(account: account, store: accountMutationStore)
        adultContent = AdultContentController()
        regionSettings = RegionSettings()
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
        if let catalog = catalog as? any CatalogV2Repository {
            capabilities = try? await catalog.capabilities()
        }
        await accountSession.refresh()
        if case .signedIn(let profile) = accountSession.state,
           let sync = library as? any LibrarySyncRepository {
            try? sync.activateAccount(profile.id)
            _ = await accountMutations.flush(accountID: profile.id)
        }
    }

    public func syncAccountLibrary(language: String) async {
        guard case .signedIn(let profile) = accountSession.state,
              let sync = library as? any LibrarySyncRepository else { return }
        do {
            try sync.activateAccount(profile.id)
            for collection in LibraryCollection.allCases {
                for mediaType in MediaType.allCases {
                    var page = 1
                    var values: [TitleSummary] = []
                    repeat {
                        let result = try await account.library(
                            collection,
                            mediaType: mediaType,
                            page: page,
                            language: language
                        )
                        values.append(contentsOf: result.results)
                        if page >= result.totalPages { break }
                        page += 1
                    } while page <= 500
                    try sync.mergeRemote(values, collection: collection, mediaType: mediaType, accountID: profile.id)
                }
            }
            await flushLibraryOutbox()
            _ = await accountMutations.flush(accountID: profile.id)
        } catch {
            // The durable outbox and the local library remain authoritative while
            // the account service is offline. A later refresh retries the merge.
        }
    }

    public func flushLibraryOutbox() async {
        guard let sync = library as? any LibrarySyncRepository else { return }
        let mutations = (try? sync.pendingMutations(limit: 100)) ?? []
        for mutation in mutations {
            do {
                _ = try await account.setLibrary(
                    mutation.collection,
                    mediaType: mutation.mediaType,
                    mediaID: mutation.mediaID,
                    enabled: mutation.enabled,
                    mutationID: mutation.id
                )
                try sync.confirmMutation(mutation.id)
            } catch {
                try? sync.failMutation(mutation.id, message: error.localizedDescription)
                break
            }
        }
    }

    @discardableResult
    public func flushAccountOutbox() async -> AccountMutationFlushReport {
        guard let accountID = signedInAccountID else {
            return AccountMutationFlushReport(failure: APIError.unauthorized.localizedDescription)
        }
        return await accountMutations.flush(accountID: accountID)
    }

    public func queueTitleRating(mediaType: MediaType, mediaID: Int, value: Double?) async throws -> UUID {
        let accountID = try requireSignedInAccountID()
        return try await accountMutations.enqueue(
            .titleRating(mediaType: mediaType, mediaID: mediaID, value: value),
            accountID: accountID
        ).id
    }

    public func queueEpisodeRating(
        seriesID: Int,
        seasonNumber: Int,
        episodeNumber: Int,
        value: Double?
    ) async throws -> UUID {
        let accountID = try requireSignedInAccountID()
        return try await accountMutations.enqueue(
            .episodeRating(
                seriesID: seriesID,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber,
                value: value
            ),
            accountID: accountID
        ).id
    }

    public func queueCreateList(
        name: String,
        description: String,
        isPublic: Bool,
        region: String,
        language: String
    ) async throws -> AccountPendingMutation {
        let accountID = try requireSignedInAccountID()
        let receipt = try await accountMutations.enqueue(
            .createList(
                name: name,
                description: description,
                isPublic: isPublic,
                region: region,
                language: language
            ),
            accountID: accountID
        )
        return AccountPendingMutation(
            id: receipt.id,
            accountID: accountID,
            payload: .createList(
                name: name,
                description: description,
                isPublic: isPublic,
                region: region,
                language: language
            )
        )
    }

    public func queueUpdateList(id: Int, name: String, description: String, isPublic: Bool) async throws -> UUID {
        let accountID = try requireSignedInAccountID()
        return try await accountMutations.enqueue(
            .updateList(listID: id, name: name, description: description, isPublic: isPublic),
            accountID: accountID
        ).id
    }

    public func queueDeleteList(id: Int) async throws -> UUID {
        let accountID = try requireSignedInAccountID()
        return try await accountMutations.enqueue(.deleteList(listID: id), accountID: accountID).id
    }

    public func queueListItems(id: Int, items: [UserListItemMutation], remove: Bool) async throws -> UUID {
        let accountID = try requireSignedInAccountID()
        return try await accountMutations.enqueue(
            .mutateListItems(listID: id, items: items, remove: remove),
            accountID: accountID
        ).id
    }

    public func pendingAccountMutations() async -> [AccountPendingMutation] {
        guard let accountID = signedInAccountID else { return [] }
        return await accountMutations.pending(accountID: accountID)
    }

    public func pendingTitleRating(mediaType: MediaType, mediaID: Int) async -> PendingRating? {
        guard let accountID = signedInAccountID else { return nil }
        return await accountMutations.pendingTitleRating(
            accountID: accountID,
            mediaType: mediaType,
            mediaID: mediaID
        )
    }

    public func pendingEpisodeRating(seriesID: Int, seasonNumber: Int, episodeNumber: Int) async -> PendingRating? {
        guard let accountID = signedInAccountID else { return nil }
        return await accountMutations.pendingEpisodeRating(
            accountID: accountID,
            seriesID: seriesID,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber
        )
    }

    public func cancelPendingList(localID: Int) async throws {
        guard localID < 0 else { return }
        let pending = await pendingAccountMutations()
        guard let mutation = pending.first(where: { $0.localListID == localID }) else { return }
        try await accountMutations.cancel(mutation.id)
    }

    public func removeAccountMutationData() async {
        guard let accountID = signedInAccountID else { return }
        try? await accountMutations.clear(accountID: accountID)
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

    private var signedInAccountID: Int? {
        guard case .signedIn(let profile) = accountSession.state else { return nil }
        return profile.id
    }

    private func requireSignedInAccountID() throws -> Int {
        guard let accountID = signedInAccountID else { throw APIError.unauthorized }
        return accountID
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
