import XCTest
@testable import SmartMovieKit

@MainActor
final class EpisodeRatingModelTests: XCTestCase {
    private let context = EpisodeRatingContext(accountID: 42, seriesID: 1399, seasonNumber: 1, episodeNumber: 2)

    func testHydratesRemoteRatingPreservesKnownValueOnFailureAndRetriesRemoval() async throws {
        let model = EpisodeRatingModel()
        let repository = ControlledEpisodeStateRepository()
        let outbox = EpisodePendingStub()
        let first = Task { await model.reload(context: context, repository: repository, outbox: outbox) }
        try await waitUntil { await repository.count() == 1 }
        await repository.succeed(0, value: 0.5)
        await first.value
        XCTAssertEqual(model.value, 0.5)

        let failed = Task { await model.reload(context: context, repository: repository, outbox: outbox) }
        try await waitUntil { await repository.count() == 2 }
        await repository.fail(1)
        await failed.value
        XCTAssertEqual(model.value, 0.5)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)

        let retry = Task { await model.reload(context: context, repository: repository, outbox: outbox) }
        try await waitUntil { await repository.count() == 3 }
        await repository.succeed(2, value: nil)
        await retry.value
        XCTAssertNil(model.value)
        XCTAssertNil(model.errorMessage)
    }

    func testPendingHalfStepAndRemovalSkipRemoteAndRemainAccountScoped() async {
        for value: Double? in [0.5, nil] {
            let model = EpisodeRatingModel()
            let repository = ControlledEpisodeStateRepository()
            let outbox = EpisodePendingStub()
            await outbox.set(PendingRating(value: value), for: context)
            await model.reload(context: context, repository: repository, outbox: outbox)
            XCTAssertEqual(model.value, value)
            XCTAssertFalse(model.isLoading)
            XCTAssertNil(model.errorMessage)
            let calls = await repository.count()
            XCTAssertEqual(calls, 0)
            let foreign = await outbox.pendingEpisodeRating(accountID: 99, seriesID: 1399, seasonNumber: 1, episodeNumber: 2)
            XCTAssertNil(foreign)
        }
    }

    func testNewPendingMutationWinsOverInFlightSuccessAndFailure() async throws {
        for succeeds in [true, false] {
            for value: Double? in [0.5, nil] {
                let model = EpisodeRatingModel()
                let repository = ControlledEpisodeStateRepository()
                let outbox = EpisodePendingStub()
                let loading = Task { await model.reload(context: context, repository: repository, outbox: outbox) }
                try await waitUntil { await repository.count() == 1 }
                await outbox.set(PendingRating(value: value), for: context)
                if succeeds { await repository.succeed(0, value: 9.5) } else { await repository.fail(0) }
                await loading.value
                XCTAssertEqual(model.value, value)
                XCTAssertNil(model.errorMessage)
                XCTAssertFalse(model.isLoading)
            }
        }
    }

    func testLocallyAcknowledgedMutationInvalidatesReadStartedBeforeIt() async throws {
        for value: Double? in [0.5, nil] {
            let model = EpisodeRatingModel()
            let repository = ControlledEpisodeStateRepository()
            let outbox = EpisodePendingStub()
            let loading = Task { await model.reload(context: context, repository: repository, outbox: outbox) }
            try await waitUntil { await repository.count() == 1 }
            // The write has already been acknowledged/removed from the outbox by the time this read returns.
            model.applyLocalValue(value, for: context)
            await repository.succeed(0, value: 9.5)
            await loading.value
            XCTAssertEqual(model.value, value)
            XCTAssertFalse(model.isLoading)
        }
    }

    func testAccountAndEpisodeSwitchRejectOldSuccessAndErrorWithoutStoppingNewLoad() async throws {
        let destinations = [
            EpisodeRatingContext(accountID: 99, seriesID: 1399, seasonNumber: 1, episodeNumber: 2),
            EpisodeRatingContext(accountID: 42, seriesID: 1399, seasonNumber: 1, episodeNumber: 3)
        ]
        for destination in destinations {
            for succeeds in [true, false] {
                let model = EpisodeRatingModel()
                let repository = ControlledEpisodeStateRepository()
                let outbox = EpisodePendingStub()
                let old = Task { await model.reload(context: context, repository: repository, outbox: outbox) }
                try await waitUntil { await repository.count() == 1 }
                let current = Task { await model.reload(context: destination, repository: repository, outbox: outbox) }
                try await waitUntil { await repository.count() == 2 }
                if succeeds { await repository.succeed(0, value: 9.5) } else { await repository.fail(0) }
                await old.value
                XCTAssertNil(model.value)
                XCTAssertNil(model.errorMessage)
                XCTAssertTrue(model.isLoading)
                await repository.succeed(1, value: 0.5)
                await current.value
                XCTAssertEqual(model.value, 0.5)
                XCTAssertFalse(model.isLoading)
            }
        }
    }

    func testResetOnLogoutOrDisappearRejectsLateSuccessAndFailure() async throws {
        for succeeds in [true, false] {
            let model = EpisodeRatingModel()
            let repository = ControlledEpisodeStateRepository()
            let outbox = EpisodePendingStub()
            let loading = Task { await model.reload(context: context, repository: repository, outbox: outbox) }
            try await waitUntil { await repository.count() == 1 }
            model.reset()
            if succeeds { await repository.succeed(0, value: 9.5) } else { await repository.fail(0) }
            await loading.value
            XCTAssertNil(model.value)
            XCTAssertNil(model.errorMessage)
            XCTAssertFalse(model.isLoading)
        }
    }

    func testCancellationDoesNotAcceptNonCooperativeRemoteResponse() async throws {
        let model = EpisodeRatingModel()
        let repository = ControlledEpisodeStateRepository()
        let outbox = EpisodePendingStub()
        let loading = Task { await model.reload(context: context, repository: repository, outbox: outbox) }
        try await waitUntil { await repository.count() == 1 }
        loading.cancel()
        await repository.succeed(0, value: 9.5)
        await loading.value
        XCTAssertNil(model.value)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
    }

    func testWrongEpisodeIdentityIsRejected() async throws {
        let model = EpisodeRatingModel()
        let repository = ControlledEpisodeStateRepository()
        let outbox = EpisodePendingStub()
        let loading = Task { await model.reload(context: context, repository: repository, outbox: outbox) }
        try await waitUntil { await repository.count() == 1 }
        await repository.succeed(0, value: 9.5, wrongEpisode: true)
        await loading.value
        XCTAssertNil(model.value)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for the controlled account request")
        throw URLError(.timedOut)
    }
}

private actor EpisodePendingStub: PendingEpisodeRatingLoading {
    private var values: [EpisodeRatingContext: PendingRating] = [:]
    func set(_ value: PendingRating, for context: EpisodeRatingContext) { values[context] = value }
    func pendingEpisodeRating(accountID: Int, seriesID: Int, seasonNumber: Int, episodeNumber: Int) -> PendingRating? {
        values[EpisodeRatingContext(accountID: accountID, seriesID: seriesID, seasonNumber: seasonNumber, episodeNumber: episodeNumber)]
    }
}

private actor ControlledEpisodeStateRepository: EpisodeAccountStateLoading {
    private struct Request { let series: Int; let season: Int; let episode: Int }
    private var requests: [Request] = []
    private var continuations: [Int: CheckedContinuation<EpisodeAccountState, Error>] = [:]
    func count() -> Int { requests.count }
    func episodeAccountState(seriesID: Int, season: Int, episode: Int) async throws -> EpisodeAccountState {
        let index = requests.count
        requests.append(Request(series: seriesID, season: season, episode: episode))
        return try await withCheckedThrowingContinuation { continuations[index] = $0 }
    }
    func succeed(_ index: Int, value: Double?, wrongEpisode: Bool = false) {
        let request = requests[index]
        continuations.removeValue(forKey: index)?.resume(returning: EpisodeAccountState(
            seriesId: request.series, seasonNumber: request.season,
            episodeNumber: wrongEpisode ? request.episode + 1 : request.episode,
            rated: value.map { .object(["value": .number($0)]) } ?? .bool(false)
        ))
    }
    func fail(_ index: Int) {
        continuations.removeValue(forKey: index)?.resume(throwing: APIError.server(status: 503, requestID: "episode-test"))
    }
}
