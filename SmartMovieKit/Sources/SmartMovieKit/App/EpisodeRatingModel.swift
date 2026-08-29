import Foundation
import Observation

struct EpisodeRatingContext: Hashable, Sendable {
    let accountID: Int
    let seriesID: Int
    let seasonNumber: Int
    let episodeNumber: Int
}

protocol PendingEpisodeRatingLoading: Sendable {
    func pendingEpisodeRating(accountID: Int, seriesID: Int, seasonNumber: Int, episodeNumber: Int) async -> PendingRating?
}

extension AccountMutationCoordinator: PendingEpisodeRatingLoading {}

@MainActor
@Observable
final class EpisodeRatingModel {
    private(set) var value: Double?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var context: EpisodeRatingContext?
    private var generation = 0

    func reset() {
        generation += 1
        context = nil
        value = nil
        isLoading = false
        errorMessage = nil
    }

    func applyLocalValue(_ value: Double?, for context: EpisodeRatingContext) {
        guard self.context == context else { return }
        generation += 1
        self.value = value
        isLoading = false
        errorMessage = nil
    }

    func reload(
        context: EpisodeRatingContext,
        repository: any EpisodeAccountStateLoading,
        outbox: any PendingEpisodeRatingLoading
    ) async {
        if self.context != context { reset() }
        self.context = context
        generation += 1
        let requestGeneration = generation
        isLoading = true
        errorMessage = nil
        defer { if generation == requestGeneration { isLoading = false } }

        let pending = await pendingRating(context, outbox: outbox)
        guard isCurrent(requestGeneration) else { return }
        if let pending {
            value = pending.value
            return
        }
        do {
            let remote = try await repository.episodeAccountState(
                seriesID: context.seriesID, season: context.seasonNumber, episode: context.episodeNumber
            )
            guard isCurrent(requestGeneration) else { return }
            guard remote.seriesId == context.seriesID,
                  remote.seasonNumber == context.seasonNumber,
                  remote.episodeNumber == context.episodeNumber else { throw APIError.invalidResponse }
            let latestPending = await pendingRating(context, outbox: outbox)
            guard isCurrent(requestGeneration) else { return }
            value = if let latestPending { latestPending.value } else { remote.ratingValue }
        } catch is CancellationError {
            return
        } catch {
            let latestPending = await pendingRating(context, outbox: outbox)
            guard isCurrent(requestGeneration) else { return }
            if let latestPending {
                value = latestPending.value
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func isCurrent(_ requestGeneration: Int) -> Bool {
        !Task.isCancelled && generation == requestGeneration
    }

    private func pendingRating(_ context: EpisodeRatingContext, outbox: any PendingEpisodeRatingLoading) async -> PendingRating? {
        await outbox.pendingEpisodeRating(
            accountID: context.accountID, seriesID: context.seriesID,
            seasonNumber: context.seasonNumber, episodeNumber: context.episodeNumber
        )
    }
}
