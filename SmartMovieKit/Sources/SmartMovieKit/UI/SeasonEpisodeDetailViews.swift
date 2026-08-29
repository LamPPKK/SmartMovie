import SwiftUI

struct EpisodeProgressRowLayout<Content: View>: View {
    let isWatched: Bool
    let actionTitle: String
    let accessibilityLabel: String
    let onToggle: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            content.frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onToggle) {
                Label(actionTitle, systemImage: isWatched ? "checkmark.circle.fill" : "circle")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .foregroundStyle(isWatched ? CinemaTheme.accent : CinemaTheme.muted)
            .accessibilityLabel(accessibilityLabel)
        }
    }

}

enum EpisodeProgressPresentation {
    static func actionAccessibilityLabel(
        action: String, episodeLabel: String, episodeNumber: Int, episodeName: String
    ) -> String {
        "\(action), \(episodeLabel) \(episodeNumber): \(episodeName)"
    }
}

public struct SeasonDetailView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.locale) private var locale
    @State private var state: Loadable<SeasonDetail> = .idle
    @State private var watchedEpisodes: Set<Int> = []
    @State private var progressError: String?
    private let route: SeasonRoute

    public init(route: SeasonRoute) { self.route = route }

    public var body: some View {
        Group {
            switch state {
            case .idle, .loading: ProgressView()
            case .failed(let message):
                StateMessageView(
                    icon: "tv",
                    title: String(localized: "Season unavailable", bundle: .module),
                    message: message
                )
            case .loaded(let detail):
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if detail.posterPath != nil {
                            RemoteArtwork(
                                url: container.imageURL(path: detail.posterPath, kind: .poster),
                                kind: .poster
                            )
                            .frame(width: 220, height: 330)
                            .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.cornerRadius))
                        }
                        Text(detail.name).font(.system(.largeTitle, design: .serif, weight: .black))
                        if !detail.overview.isEmpty { Text(detail.overview).foregroundStyle(CinemaTheme.muted) }
                        CatalogMetadataSection(
                            values: seasonMetadata(detail),
                            externalIDs: detail.externalIDs
                        )
                        CatalogMediaSection(images: detail.images, videos: detail.videos)
                        CreditShelf(title: String(localized: "Cast", bundle: .module), credits: detail.credits.cast)
                        CreditShelf(title: String(localized: "Crew", bundle: .module), credits: detail.credits.crew)
                        if !detail.episodes.isEmpty {
                            let episodeNumbers = Set(detail.episodes.map(\.episodeNumber))
                            let watchedCount = watchedEpisodes.intersection(episodeNumbers).count
                            VStack(alignment: .leading, spacing: 10) {
                                let progressLabel = String(
                                    format: String(localized: "Watched %d of %d", bundle: .module),
                                    watchedCount, detail.episodes.count
                                )
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(progressLabel).font(.headline)
                                    ProgressView(value: Double(watchedCount), total: Double(detail.episodes.count))
                                        .tint(CinemaTheme.accent)
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(String(localized: "Episode progress", bundle: .module))
                                .accessibilityValue(progressLabel)
                                Button {
                                    setSeasonWatched(watchedCount != detail.episodes.count, detail: detail)
                                } label: {
                                    Label(
                                        String(localized: watchedCount == detail.episodes.count
                                            ? "Mark season unwatched" : "Mark season watched", bundle: .module),
                                        systemImage: watchedCount == detail.episodes.count
                                            ? "checkmark.circle.fill" : "checkmark.circle"
                                    )
                                    .frame(minHeight: 44)
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.vertical, 4)
                        }
                        ForEach(detail.episodes) { episode in
                            let watched = watchedEpisodes.contains(episode.episodeNumber)
                            let action = String(localized: watched ? "Mark as unwatched" : "Mark as watched", bundle: .module)
                            EpisodeProgressRowLayout(
                                isWatched: watched,
                                actionTitle: action,
                                accessibilityLabel: EpisodeProgressPresentation.actionAccessibilityLabel(
                                    action: action,
                                    episodeLabel: String(localized: "Episode", bundle: .module),
                                    episodeNumber: episode.episodeNumber,
                                    episodeName: episode.name
                                ),
                                onToggle: { setEpisodeWatched(!watched, episode: episode) },
                                content: {
                                NavigationLink(value: EpisodeRoute(
                                    series: route.series,
                                    seasonNumber: detail.seasonNumber,
                                    episode: episode
                                )) {
                                    EpisodeRow(episode: episode)
                                }
                                .buttonStyle(.plain)
                            })
                        }
                    }
                    .padding(24)
                }
            }
        }
        .navigationTitle(route.season.name)
        .cinemaScreen()
        .task { await load() }
        .task(id: container.episodeProgressRevision) { reloadProgress() }
        .alert(String(localized: "Episode progress", bundle: .module), isPresented: Binding(
            get: { progressError != nil }, set: { if !$0 { progressError = nil } }
        )) { Button(String(localized: "OK", bundle: .module), role: .cancel) {} } message: {
            Text(progressError ?? "")
        }
    }

    private func load() async {
        guard case .idle = state, let catalog = container.catalog as? any CatalogV2Repository else { return }
        state = .loading
        do {
            let detail = try await catalog.season(
                seriesID: route.seriesID,
                number: route.season.seasonNumber,
                language: LocaleResolver.tmdbLanguage(for: locale)
            )
            state = .loaded(detail)
            reloadProgress()
        } catch { state = .failed(error.localizedDescription) }
    }

    private func reloadProgress() {
        guard case .loaded(let detail) = state else { return }
        do {
            watchedEpisodes = try container.watchedEpisodeNumbers(
                seriesID: detail.seriesId, seasonNumber: detail.seasonNumber
            )
        } catch { progressError = error.localizedDescription }
    }

    private func setEpisodeWatched(_ watched: Bool, episode: EpisodeSummary) {
        do {
            try container.setEpisodeWatched(watched, key: EpisodeWatchKey(
                seriesID: episode.seriesId,
                seasonNumber: episode.seasonNumber,
                episodeNumber: episode.episodeNumber
            ))
            reloadProgress()
        } catch { progressError = error.localizedDescription }
    }

    private func setSeasonWatched(_ watched: Bool, detail: SeasonDetail) {
        do {
            try container.setSeasonWatched(
                watched,
                seriesID: detail.seriesId,
                seasonNumber: detail.seasonNumber,
                episodeNumbers: detail.episodes.map(\.episodeNumber)
            )
            reloadProgress()
        } catch { progressError = error.localizedDescription }
    }

    private func seasonMetadata(_ detail: SeasonDetail) -> [(label: String, value: String)] {
        var values: [(label: String, value: String)] = []
        if let airDate = detail.airDate {
            values.append((String(localized: "Air date", bundle: .module), String(airDate.prefix(10))))
        }
        values.append((String(localized: "Episodes", bundle: .module), "\(detail.episodeCount)"))
        return values
    }
}

public struct EpisodeDetailView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.locale) private var locale
    @State private var state: Loadable<EpisodeDetail> = .idle
    @State private var isWatched = false
    @State private var progressError: String?
    private let route: EpisodeRoute

    public init(route: EpisodeRoute) { self.route = route }

    public var body: some View {
        Group {
            switch state {
            case .idle, .loading: ProgressView()
            case .failed(let message):
                StateMessageView(
                    icon: "play.rectangle",
                    title: String(localized: "Episode unavailable", bundle: .module),
                    message: message
                )
            case .loaded(let detail):
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        RemoteArtwork(
                            url: container.imageURL(path: detail.stillPath, kind: .backdrop),
                            kind: .backdrop
                        )
                            .frame(height: 320)
                            .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.cornerRadius))
                        Text("S\(detail.seasonNumber) · E\(detail.episodeNumber)")
                            .font(.caption.weight(.black)).foregroundStyle(CinemaTheme.accent)
                        Text(detail.name).font(.system(.largeTitle, design: .serif, weight: .black))
                        Text(detail.overview.isEmpty ? String(localized: "No overview is available.", bundle: .module) : detail.overview)
                            .lineSpacing(4)
                        CatalogMetadataSection(
                            values: episodeMetadata(detail),
                            externalIDs: detail.externalIDs
                        )
                        Button { setWatched(!isWatched, detail: detail) } label: {
                            Label(
                                String(localized: isWatched ? "Mark as unwatched" : "Mark as watched", bundle: .module),
                                systemImage: isWatched ? "checkmark.circle.fill" : "checkmark.circle"
                            )
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(CinemaTheme.accent)
                        CatalogMediaSection(images: detail.images, videos: detail.videos)
                        CreditShelf(title: String(localized: "Guest stars", bundle: .module), credits: detail.guestStars)
                        CreditShelf(title: String(localized: "Crew", bundle: .module), credits: detail.crew)
                        if let accountID = container.ratingAccountID {
                            let context = EpisodeRatingContext(
                                accountID: accountID, seriesID: detail.seriesId,
                                seasonNumber: detail.seasonNumber, episodeNumber: detail.episodeNumber
                            )
                            EpisodeRatingView(context: context).id(context)
                        }
                    }
                    .frame(maxWidth: 900, alignment: .leading)
                    .padding(24)
                }
            }
        }
        .navigationTitle(route.episode.name)
        .cinemaScreen()
        .task { await load() }
        .task(id: container.episodeProgressRevision) { reloadProgress() }
        .onDisappear {
            container.watchRemoteSession?.clear(contextKey: "episode:\(route.episode.episodeKey)")
        }
        .alert(String(localized: "Episode progress", bundle: .module), isPresented: Binding(
            get: { progressError != nil }, set: { if !$0 { progressError = nil } }
        )) { Button(String(localized: "OK", bundle: .module), role: .cancel) {} } message: {
            Text(progressError ?? "")
        }
    }

    private func load() async {
        guard case .idle = state, let catalog = container.catalog as? any CatalogV2Repository else { return }
        state = .loading
        do {
            let detail = try await catalog.episode(
                seriesID: route.seriesID,
                season: route.seasonNumber,
                number: route.episode.episodeNumber,
                language: LocaleResolver.tmdbLanguage(for: locale)
            )
            state = .loaded(detail)
            reloadProgress()
            syncWatchRemote(detail)
        } catch { state = .failed(error.localizedDescription) }
    }

    private func reloadProgress() {
        guard case .loaded(let detail) = state else { return }
        do {
            isWatched = try container.isEpisodeWatched(EpisodeWatchKey(
                seriesID: detail.seriesId,
                seasonNumber: detail.seasonNumber,
                episodeNumber: detail.episodeNumber
            ))
        } catch { progressError = error.localizedDescription }
    }

    private func setWatched(_ watched: Bool, detail: EpisodeDetail) {
        do {
            try container.setEpisodeWatched(watched, key: EpisodeWatchKey(
                seriesID: detail.seriesId,
                seasonNumber: detail.seasonNumber,
                episodeNumber: detail.episodeNumber
            ))
            isWatched = watched
        } catch { progressError = error.localizedDescription }
    }

    private func episodeMetadata(_ detail: EpisodeDetail) -> [(label: String, value: String)] {
        var values: [(label: String, value: String)] = []
        if let airDate = detail.airDate {
            values.append((String(localized: "Air date", bundle: .module), String(airDate.prefix(10))))
        }
        if let runtime = detail.runtimeMinutes {
            values.append((
                String(localized: "Runtime", bundle: .module),
                String(format: String(localized: "%d min", bundle: .module), runtime)
            ))
        }
        if let productionCode = detail.productionCode, !productionCode.isEmpty {
            values.append((String(localized: "Production code", bundle: .module), productionCode))
        }
        if let voteAverage = detail.voteAverage {
            values.append((String(localized: "Rating", bundle: .module), String(format: "%.1f / 10", voteAverage)))
        }
        values.append((String(localized: "Votes", bundle: .module), "\(detail.voteCount)"))
        return values
    }

    private func syncWatchRemote(_ detail: EpisodeDetail) {
        guard !route.series.isAdult else { return }
        let episode = EpisodeSummary(
            id: detail.id,
            seriesId: detail.seriesId,
            seasonNumber: detail.seasonNumber,
            episodeNumber: detail.episodeNumber,
            name: detail.name,
            overview: detail.overview,
            stillPath: detail.stillPath,
            airDate: detail.airDate,
            runtimeMinutes: detail.runtimeMinutes,
            voteAverage: detail.voteAverage
        )
        container.watchRemoteSession?.update(
            context: WatchRemoteContext(
                title: route.series,
                episode: episode,
                artworkURL: container.imageURL(path: detail.stillPath, kind: .backdrop),
                isFavorite: false,
                isWatchlisted: false,
                hasTrailer: false
            )
        )
    }

}
