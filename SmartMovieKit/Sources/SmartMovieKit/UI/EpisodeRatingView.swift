import SwiftUI

struct EpisodeRatingView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.locale) private var locale
    @State private var model = EpisodeRatingModel()
    @State private var mutationError: String?
    let context: EpisodeRatingContext

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Menu {
                AccountRatingOptions(currentRating: model.value) { value in
                    Task { await setRating(value) }
                }
            } label: {
                Label(
                    model.value.map { $0.formatted(.number.precision(.fractionLength(0...1)).locale(locale)) }
                        ?? String(localized: "Rate episode", bundle: .module),
                    systemImage: model.value == nil ? "star" : "star.fill"
                )
                .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(CinemaTheme.accent)
            if model.isLoading {
                ProgressView(String(localized: "Rating", bundle: .module))
            }
            if let message = model.errorMessage {
                Text(message).font(.footnote).foregroundStyle(CinemaTheme.muted)
                Button(String(localized: "Try again", bundle: .module)) { Task { await reload() } }
                    .frame(minHeight: 44)
            }
        }
        .task { await reload() }
        .onDisappear { model.reset() }
        .alert(String(localized: "Rating", bundle: .module), isPresented: Binding(
            get: { mutationError != nil },
            set: { if !$0 { mutationError = nil } }
        )) { Button(String(localized: "OK", bundle: .module), role: .cancel) {} } message: { Text(mutationError ?? "") }
    }

    private func reload() async {
        guard container.ratingAccountID == context.accountID else { model.reset(); return }
        await model.reload(context: context, repository: container.account, outbox: container.accountMutations)
    }

    private func setRating(_ value: Double?) async {
        guard container.ratingAccountID == context.accountID else { return }
        do {
            _ = try await container.queueEpisodeRating(
                seriesID: context.seriesID, seasonNumber: context.seasonNumber,
                episodeNumber: context.episodeNumber, value: value
            )
            guard container.ratingAccountID == context.accountID else { return }
            model.applyLocalValue(value, for: context)
            _ = await container.flushAccountOutbox()
        } catch {
            guard container.ratingAccountID == context.accountID else { return }
            mutationError = error.localizedDescription
        }
    }
}
