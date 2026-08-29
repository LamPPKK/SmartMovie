import Foundation
import XCTest
@testable import SmartMovieKit

final class AccountCapabilityGateTests: XCTestCase {
    func testRatingGateRequiresSignedInAccountRatingsAndPlatformAuthenticationCapability() {
        let profile = AccountProfile(
            id: 42, username: "fixture", name: "Fixture", language: nil, country: nil,
            includeAdult: false, avatarPath: nil, gravatarHash: nil
        )
        let signedIn = AccountSessionController.State.signedIn(profile)
        XCTAssertNil(signedIn.ratingAccountID(capabilities: nil, mode: "browser"))
        for ratings in [true, false] {
            for browser in [true, false] {
                for television in [true, false] {
                    let capabilities = CapabilitiesV2(
                        apiVersion: "v2", releaseTrain: "3.0.0", catalog: [:],
                        account: ["ratings": ratings, "browser_auth": browser, "tv_qr_auth": television]
                    )
                    XCTAssertEqual(signedIn.ratingAccountID(capabilities: capabilities, mode: "browser"), ratings && browser ? 42 : nil)
                    XCTAssertEqual(signedIn.ratingAccountID(capabilities: capabilities, mode: "tv"), ratings && television ? 42 : nil)
                    for state: AccountSessionController.State in [.checking, .signedOut, .authorizing, .failed("offline")] {
                        XCTAssertNil(state.ratingAccountID(capabilities: capabilities, mode: "browser"))
                        XCTAssertNil(state.ratingAccountID(capabilities: capabilities, mode: "tv"))
                    }
                }
            }
        }
        let missingRatings = CapabilitiesV2(
            apiVersion: "v2", releaseTrain: "3.0.0", catalog: [:], account: ["browser_auth": true]
        )
        XCTAssertNil(signedIn.ratingAccountID(capabilities: missingRatings, mode: "browser"))
    }

    @MainActor
    func testDisabledSessionDoesNotCompleteCallback() async throws {
        let account = CompletionAccountRepository()
        let controller = AccountSessionController(account: account)
        let callback = try XCTUnwrap(
            URL(string: "smartmovie://auth/callback?auth_attempt=00000000-0000-0000-0000-000000000001")
        )

        await controller.handleCallback(callback)

        let completionCalls = await account.completionCallCount()
        XCTAssertEqual(completionCalls, 0)
        guard case .checking = controller.state else {
            return XCTFail("A pre-capability callback must not change session state")
        }
    }

    @MainActor
    func testDisableInvalidatesCompletionAlreadyInFlight() async {
        let account = CompletionAccountRepository()
        let controller = AccountSessionController(account: account)
        controller.enable()

        let completion = Task {
            await controller.complete(id: UUID(), deviceCode: nil)
        }
        await account.waitUntilCompletionStarts()
        controller.disable()
        await account.releaseCompletion()
        await completion.value

        let completionCalls = await account.completionCallCount()
        XCTAssertEqual(completionCalls, 1)
        guard case .signedOut = controller.state else {
            return XCTFail("A stale completion must not restore a signed-in state")
        }
    }

    @MainActor
    func testUnavailableCapabilityKeepsDurableLibraryMutationOffline() async {
        let account = CompletionAccountRepository()
        let library = RecordingLibrarySyncRepository()
        let container = AppContainer(
            catalog: UnavailableCatalogRepository(),
            library: library,
            account: account
        )

        await container.flushLibraryOutbox()

        XCTAssertEqual(library.pendingReads, 0)
        let mutationCalls = await account.libraryMutationCallCount()
        XCTAssertEqual(mutationCalls, 0)
    }
}

private actor CompletionAccountRepository: AccountRepository {
    private var completionCalls = 0
    private var libraryMutationCalls = 0
    private var completionStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var completionContinuation: CheckedContinuation<Void, Never>?

    func completionCallCount() -> Int { completionCalls }
    func libraryMutationCallCount() -> Int { libraryMutationCalls }

    func waitUntilCompletionStarts() async {
        if completionStarted { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func releaseCompletion() {
        completionContinuation?.resume()
        completionContinuation = nil
    }

    func completeAuth(id: UUID, deviceCode: String?) async throws -> AuthSession {
        completionCalls += 1
        completionStarted = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await withCheckedContinuation { completionContinuation = $0 }
        return AuthSession(
            sessionToken: "opaque",
            csrfToken: "csrf",
            expiresAt: .distantFuture,
            profile: AccountProfile(
                id: 7,
                username: "fixture",
                name: "Fixture",
                language: "en",
                country: "US",
                includeAdult: false,
                avatarPath: nil,
                gravatarHash: nil
            )
        )
    }

    func createAuthAttempt(returnURI: URL, mode: String) async throws -> AuthAttempt { throw APIError.unauthorized }
    func authAttempt(id: UUID, deviceCode: String?) async throws -> String { throw APIError.unauthorized }
    func profile() async throws -> AccountProfile { throw APIError.unauthorized }
    func accountState(mediaType: MediaType, id: Int) async throws -> AccountState { throw APIError.unauthorized }
    func episodeAccountState(seriesID: Int, season: Int, episode: Int) async throws -> EpisodeAccountState {
        throw APIError.unauthorized
    }
    func logout() async throws { throw APIError.unauthorized }
    func library(
        _ collection: LibraryCollection,
        mediaType: MediaType,
        page: Int,
        language: String
    ) async throws -> PagedResult<TitleSummary> { throw APIError.unauthorized }
    func setLibrary(
        _ collection: LibraryCollection,
        mediaType: MediaType,
        mediaID: Int,
        enabled: Bool,
        mutationID: UUID
    ) async throws -> MutationResult {
        libraryMutationCalls += 1
        throw APIError.unauthorized
    }
    func setRating(
        mediaType: MediaType,
        id: Int,
        value: Double?,
        mutationID: UUID
    ) async throws -> MutationResult { throw APIError.unauthorized }
    func setEpisodeRating(
        seriesID: Int,
        season: Int,
        episode: Int,
        value: Double?,
        mutationID: UUID
    ) async throws -> MutationResult { throw APIError.unauthorized }
    func recommendations(
        mediaType: MediaType,
        page: Int,
        language: String
    ) async throws -> PagedResult<TitleSummary> { throw APIError.unauthorized }
    func lists(page: Int) async throws -> PagedResult<UserList> { throw APIError.unauthorized }
    func list(id: Int, page: Int, language: String) async throws -> UserList { throw APIError.unauthorized }
    func createList(
        _ metadata: UserListMetadataMutation,
        mutationID: UUID
    ) async throws -> MutationResult { throw APIError.unauthorized }
    func updateList(
        id: Int,
        name: String,
        description: String,
        isPublic: Bool,
        mutationID: UUID
    ) async throws -> MutationResult { throw APIError.unauthorized }
    func deleteList(id: Int, mutationID: UUID) async throws -> MutationResult { throw APIError.unauthorized }
    func mutateListItems(
        id: Int,
        items: [UserListItemMutation],
        remove: Bool,
        mutationID: UUID
    ) async throws -> MutationResult { throw APIError.unauthorized }
}

private actor UnavailableCatalogRepository: CatalogRepository {
    func home(mediaType: MediaType, language: String) async throws -> HomeFeed { throw APIError.unauthorized }
    func genres(mediaType: MediaType, language: String) async throws -> [Genre] { throw APIError.unauthorized }
    func discover(
        mediaType: MediaType,
        filter: DiscoverFilter,
        page: Int,
        language: String
    ) async throws -> PagedResult<TitleSummary> { throw APIError.unauthorized }
    func search(
        query: String,
        scope: SearchScope,
        page: Int,
        language: String
    ) async throws -> PagedResult<TitleSummary> { throw APIError.unauthorized }
    func detail(mediaType: MediaType, id: Int, language: String) async throws -> TitleDetail {
        throw APIError.unauthorized
    }
    func imageConfiguration() async throws -> ImageConfiguration { throw APIError.unauthorized }
}

@MainActor
private final class RecordingLibrarySyncRepository: LibrarySyncRepository {
    private(set) var pendingReads = 0

    func contains(_ title: TitleSummary, in collection: LibraryCollection) throws -> Bool { false }
    func toggle(_ title: TitleSummary, in collection: LibraryCollection) throws {}
    func items(
        in collection: LibraryCollection,
        mediaType: MediaType?,
        sort: LibrarySort
    ) throws -> [LibrarySnapshot] { [] }
    func reconcileDuplicates() throws {}
    func activateAccount(_ accountID: Int) throws {}
    func deactivateAccount(removeAccountData: Bool) throws {}
    func mergeRemote(
        _ remote: [TitleSummary],
        collection: LibraryCollection,
        mediaType: MediaType,
        accountID: Int
    ) throws {}
    func pendingMutations(limit: Int) throws -> [LibraryPendingMutation] {
        pendingReads += 1
        return []
    }
    func confirmMutation(_ id: UUID) throws {}
    func failMutation(_ id: UUID, message: String) throws {}
}
