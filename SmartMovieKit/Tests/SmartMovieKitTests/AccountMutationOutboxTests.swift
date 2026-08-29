import Foundation
import XCTest
@testable import SmartMovieKit

final class AccountMutationOutboxTests: XCTestCase {
    func testFileStorePersistsNullableMutationAndIsolatesAccounts() async throws {
        let fileURL = temporaryFileURL()
        addTeardownBlock { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let firstID = try XCTUnwrap(UUID(uuidString: "00000000-0000-4000-8000-000000000101"))
        let secondID = try XCTUnwrap(UUID(uuidString: "00000000-0000-4000-8000-000000000102"))
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let firstStore = FileAccountMutationStore(fileURL: fileURL)

        try await firstStore.enqueue(AccountPendingMutation(
            id: firstID,
            accountID: 42,
            payload: .titleRating(mediaType: .movie, mediaID: 550, value: nil),
            createdAt: createdAt
        ))
        try await firstStore.enqueue(AccountPendingMutation(
            id: secondID,
            accountID: 99,
            payload: .createList(
                name: "Offline picks",
                description: "Queued without a network",
                isPublic: false,
                region: "VN",
                language: "vi"
            ),
            createdAt: createdAt.addingTimeInterval(1)
        ))

        let reloadedStore = FileAccountMutationStore(fileURL: fileURL)
        let firstAccount = await reloadedStore.pending(accountID: 42, limit: 10)
        let secondAccount = await reloadedStore.pending(accountID: 99, limit: 10)

        XCTAssertEqual(firstAccount.map(\.id), [firstID])
        XCTAssertEqual(secondAccount.map(\.id), [secondID])
        guard case .titleRating(let type, let mediaID, let value) = firstAccount[0].payload else {
            return XCTFail("Expected a title rating mutation")
        }
        XCTAssertEqual(type, .movie)
        XCTAssertEqual(mediaID, 550)
        XCTAssertNil(value)
        XCTAssertLessThan(try XCTUnwrap(secondAccount[0].localListID), 0)
    }

    func testCoordinatorRetainsMutationAndReusesIdempotencyKeyUntilAcknowledged() async throws {
        let fileURL = temporaryFileURL()
        addTeardownBlock { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let repository = FlakyAccountRepository(failuresBeforeSuccess: 1)
        let store = FileAccountMutationStore(fileURL: fileURL)
        let coordinator = AccountMutationCoordinator(
            account: repository,
            store: store,
            now: { Date(timeIntervalSince1970: 2_000) }
        )
        let mutationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-4000-8000-000000000201"))

        _ = try await coordinator.enqueue(
            .episodeRating(seriesID: 1399, seasonNumber: 1, episodeNumber: 1, value: 0.5),
            accountID: 42,
            id: mutationID
        )
        let firstFlush = await coordinator.flush(accountID: 42)
        XCTAssertNotNil(firstFlush.failure)
        let retained = await coordinator.pending(accountID: 42)
        XCTAssertEqual(retained.first?.id, mutationID)
        XCTAssertEqual(retained.first?.attemptCount, 1)

        let reloaded = AccountMutationCoordinator(account: repository, store: FileAccountMutationStore(fileURL: fileURL))
        let pendingRating = await reloaded.pendingEpisodeRating(accountID: 42, seriesID: 1399, seasonNumber: 1, episodeNumber: 1)
        XCTAssertEqual(pendingRating?.value, 0.5)
        let secondFlush = await reloaded.flush(accountID: 42)
        XCTAssertNil(secondFlush.failure)
        XCTAssertEqual(secondFlush.delivered[mutationID]?.mutationId, mutationID)
        let remaining = await reloaded.pending(accountID: 42)
        let receivedIDs = await repository.receivedMutationIDs()
        let receivedRatings = await repository.receivedRatingPayloads()
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertEqual(receivedIDs, [mutationID, mutationID])
        XCTAssertEqual(receivedRatings, Array(repeating:
            .episodeRating(seriesID: 1399, seasonNumber: 1, episodeNumber: 1, value: 0.5), count: 2))
    }

    func testEveryRatingValueAndRemovalSurviveRestartForMovieTVAndEpisode() async throws {
        let fileURL = temporaryFileURL()
        addTeardownBlock { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let store = FileAccountMutationStore(fileURL: fileURL)
        let values: [Double?] = [
            0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5,
            5.5, 6, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10, nil
        ]
        let payloads: [AccountMutationPayload] = values.flatMap { value in
            [
                .titleRating(mediaType: .movie, mediaID: 550, value: value),
                .titleRating(mediaType: .tv, mediaID: 1399, value: value),
                .episodeRating(seriesID: 1399, seasonNumber: 2, episodeNumber: 3, value: value)
            ]
        }
        for (index, payload) in payloads.enumerated() {
            try await store.enqueue(AccountPendingMutation(
                accountID: 42, payload: payload, createdAt: Date(timeIntervalSince1970: Double(index))
            ))
        }
        let repository = FlakyAccountRepository(failuresBeforeSuccess: 0)
        let reloaded = AccountMutationCoordinator(account: repository, store: FileAccountMutationStore(fileURL: fileURL))
        let pending = await reloaded.pending(accountID: 42)
        XCTAssertEqual(pending.map(\.payload), payloads)

        let report = await reloaded.flush(accountID: 42)
        let receivedRatings = await repository.receivedRatingPayloads()
        let remaining = await reloaded.pending(accountID: 42)
        XCTAssertNil(report.failure)
        XCTAssertEqual(report.delivered.count, 63)
        XCTAssertEqual(receivedRatings, payloads)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testCoordinatorDoesNotConfirmMismatchedAcknowledgement() async throws {
        let fileURL = temporaryFileURL()
        addTeardownBlock { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let repository = FlakyAccountRepository(failuresBeforeSuccess: 0, acknowledgeDifferentID: true)
        let coordinator = AccountMutationCoordinator(
            account: repository,
            store: FileAccountMutationStore(fileURL: fileURL)
        )
        let mutationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-4000-8000-000000000301"))

        _ = try await coordinator.enqueue(
            .titleRating(mediaType: .tv, mediaID: 1399, value: 8.5),
            accountID: 42,
            id: mutationID
        )
        let report = await coordinator.flush(accountID: 42)

        let retained = await coordinator.pending(accountID: 42)
        XCTAssertNotNil(report.failure)
        XCTAssertEqual(retained.first?.id, mutationID)
    }

    func testListItemSnapshotPersistsAndOlderPayloadWithoutSnapshotStillDecodes() async throws {
        let title = TitleSummary(
            id: 1399,
            mediaType: .tv,
            title: "Game of Thrones",
            originalTitle: "Game of Thrones",
            overview: ""
        )
        let payload = AccountMutationPayload.mutateListItems(
            listID: 7,
            items: [UserListItemMutation(mediaType: .tv, mediaId: title.id)],
            titles: [title],
            remove: false
        )
        let encoded = try JSONEncoder().encode(payload)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let caseKey = try XCTUnwrap(object.keys.first)
        var casePayload = try XCTUnwrap(object[caseKey] as? [String: Any])
        casePayload.removeValue(forKey: "titles")
        object[caseKey] = casePayload
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let legacy = try JSONDecoder().decode(AccountMutationPayload.self, from: legacyData)

        guard case .mutateListItems(let listID, let items, let titles, let remove) = legacy else {
            return XCTFail("Expected a list item mutation")
        }
        XCTAssertEqual(listID, 7)
        XCTAssertEqual(items.first?.mediaId, 1399)
        XCTAssertNil(titles)
        XCTAssertFalse(remove)
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SmartMovieAccountOutboxTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("outbox.json")
    }
}

private actor FlakyAccountRepository: AccountRepository {
    private var failuresRemaining: Int
    private let acknowledgeDifferentID: Bool
    private var received: [UUID] = []
    private var ratings: [AccountMutationPayload] = []

    init(failuresBeforeSuccess: Int, acknowledgeDifferentID: Bool = false) {
        failuresRemaining = failuresBeforeSuccess
        self.acknowledgeDifferentID = acknowledgeDifferentID
    }

    func receivedMutationIDs() -> [UUID] { received }
    func receivedRatingPayloads() -> [AccountMutationPayload] { ratings }

    func createAuthAttempt(returnURI: URL, mode: String) async throws -> AuthAttempt { throw APIError.unauthorized }
    func authAttempt(id: UUID, deviceCode: String?) async throws -> String { throw APIError.unauthorized }
    func completeAuth(id: UUID, deviceCode: String?) async throws -> AuthSession { throw APIError.unauthorized }
    func profile() async throws -> AccountProfile { throw APIError.unauthorized }
    func accountState(mediaType: MediaType, id: Int) async throws -> AccountState { throw APIError.unauthorized }
    func episodeAccountState(seriesID: Int, season: Int, episode: Int) async throws -> EpisodeAccountState {
        throw APIError.unauthorized
    }
    func logout() async throws {}
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
    ) async throws -> MutationResult { throw APIError.unauthorized }
    func setRating(mediaType: MediaType, id: Int, value: Double?, mutationID: UUID) async throws -> MutationResult {
        ratings.append(.titleRating(mediaType: mediaType, mediaID: id, value: value))
        return try acknowledge(mutationID)
    }
    func setEpisodeRating(
        seriesID: Int,
        season: Int,
        episode: Int,
        value: Double?,
        mutationID: UUID
    ) async throws -> MutationResult {
        ratings.append(.episodeRating(seriesID: seriesID, seasonNumber: season, episodeNumber: episode, value: value))
        return try acknowledge(mutationID)
    }
    func recommendations(mediaType: MediaType, page: Int, language: String) async throws -> PagedResult<TitleSummary> {
        throw APIError.unauthorized
    }
    func lists(page: Int) async throws -> PagedResult<UserList> { throw APIError.unauthorized }
    func list(id: Int, page: Int, language: String) async throws -> UserList { throw APIError.unauthorized }
    func createList(
        _ metadata: UserListMetadataMutation,
        mutationID: UUID
    ) async throws -> MutationResult { try acknowledge(mutationID) }
    func updateList(
        id: Int,
        name: String,
        description: String,
        isPublic: Bool,
        mutationID: UUID
    ) async throws -> MutationResult { try acknowledge(mutationID) }
    func deleteList(id: Int, mutationID: UUID) async throws -> MutationResult { try acknowledge(mutationID) }
    func mutateListItems(
        id: Int,
        items: [UserListItemMutation],
        remove: Bool,
        mutationID: UUID
    ) async throws -> MutationResult { try acknowledge(mutationID) }

    private func acknowledge(_ mutationID: UUID) throws -> MutationResult {
        received.append(mutationID)
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw APIError.transport("offline")
        }
        return MutationResult(mutationId: acknowledgeDifferentID ? UUID() : mutationID, success: true)
    }
}
