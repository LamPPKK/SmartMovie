import SwiftUI

public struct SeasonRoute: Hashable, Sendable {
    public let series: TitleSummary
    public let season: SeasonSummary

    public init(series: TitleSummary, season: SeasonSummary) {
        self.series = series
        self.season = season
    }

    @available(*, deprecated, message: "Pass the full series summary to preserve companion and privacy context.")
    public init(seriesID: Int, season: SeasonSummary) {
        self.init(
            series: TitleSummary(
                id: seriesID,
                mediaType: .tv,
                title: "",
                originalTitle: "",
                overview: "",
                isAdult: true
            ),
            season: season
        )
    }

    public var seriesID: Int { series.id }
}

public struct EpisodeRoute: Hashable, Sendable {
    public let series: TitleSummary
    public let seasonNumber: Int
    public let episode: EpisodeSummary

    public init(series: TitleSummary, seasonNumber: Int, episode: EpisodeSummary) {
        self.series = series
        self.seasonNumber = seasonNumber
        self.episode = episode
    }

    @available(*, deprecated, message: "Pass the full series summary to preserve companion and privacy context.")
    public init(seriesID: Int, seasonNumber: Int, episode: EpisodeSummary) {
        self.init(
            series: TitleSummary(
                id: seriesID,
                mediaType: .tv,
                title: "",
                originalTitle: "",
                overview: "",
                isAdult: true
            ),
            seasonNumber: seasonNumber,
            episode: episode
        )
    }

    public var seriesID: Int { series.id }
}

public struct EntityDetailView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.locale) private var locale
    @State private var state: EntityState = .loading
    private let entity: CatalogEntity

    private var includeAdult: Bool { container.adultContent.includeAdult }
    private var loadKey: String {
        "\(entity.id):\(LocaleResolver.tmdbLanguage(for: locale)):\(includeAdult)"
    }

    public init(entity: CatalogEntity) { self.entity = entity }

    public var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                StateMessageView(
                    icon: "exclamationmark.triangle",
                    title: String(localized: "Details unavailable", bundle: .module),
                    message: message,
                    retry: { Task { await load() } }
                )
            case .person(let value): person(value)
            case .collection(let value): collection(value)
            case .organization(let value): organization(value)
            case .keyword(let value): keyword(value)
            }
        }
        .navigationTitle(entity.displayName)
        .inlineNavigationTitle()
        .cinemaScreen()
        .task(id: loadKey) { await load() }
    }

    private func load() async {
        guard let catalog = container.catalog as? any CatalogV2Repository else {
            state = .failed(String(localized: "This server does not support detailed catalog entities yet.", bundle: .module))
            return
        }
        state = .loading
        do {
            let language = LocaleResolver.tmdbLanguage(for: locale)
            switch entity {
            case .person(let value):
                state = .person(try await catalog.person(
                    id: value.id,
                    language: language,
                    includeAdult: includeAdult
                ))
            case .collection(let value):
                state = .collection(try await catalog.collection(
                    id: value.id,
                    language: language,
                    includeAdult: includeAdult
                ))
            case .organization(let value):
                state = .organization(try await catalog.organization(
                    kind: value.entityKind,
                    id: value.id,
                    language: language,
                    page: 1,
                    includeAdult: includeAdult
                ))
            case .keyword(let value):
                state = .keyword(try await catalog.keyword(
                    id: value.id,
                    language: language,
                    page: 1,
                    includeAdult: includeAdult
                ))
            case .title, .season, .episode:
                state = .failed(String(localized: "This entity opens from its parent title.", bundle: .module))
            }
        } catch is CancellationError {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func person(_ value: PersonDetail) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top, spacing: 22) {
                    RemoteArtwork(url: container.imageURL(path: value.profilePath, kind: .profile), kind: .profile)
                        .frame(width: 180, height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.cornerRadius))
                    VStack(alignment: .leading, spacing: 10) {
                        Text(value.name).font(.system(.largeTitle, design: .serif, weight: .black))
                        if let department = value.knownForDepartment { Text(department).foregroundStyle(CinemaTheme.accent) }
                        if let place = value.placeOfBirth { Label(place, systemImage: "mappin.and.ellipse") }
                        if let birthday = value.birthday { Label(birthday, systemImage: "birthday.cake") }
                    }
                }
                if !value.biography.isEmpty {
                    detailSection(String(localized: "Biography", bundle: .module), text: value.biography)
                }
                titleShelf(
                    String(localized: "Known for", bundle: .module),
                    titles: CatalogAdultVisibility.titles(value.knownFor, includeAdult: includeAdult)
                )
                CreditShelf(title: String(localized: "Acting credits", bundle: .module), credits: value.credits.cast)
                CreditShelf(title: String(localized: "Crew credits", bundle: .module), credits: value.credits.crew)
            }
            .padding(24)
        }
    }

    private func collection(_ value: CollectionDetail) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                RemoteArtwork(url: container.imageURL(path: value.backdropPath ?? value.posterPath, kind: .backdrop), kind: .backdrop)
                    .frame(height: 330)
                    .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.cornerRadius))
                Text(value.name).font(.system(.largeTitle, design: .serif, weight: .black))
                if !value.overview.isEmpty { Text(value.overview).foregroundStyle(CinemaTheme.muted) }
                titleGrid(CatalogAdultVisibility.titles(value.parts, includeAdult: includeAdult))
            }
            .padding(24)
        }
    }

    private func organization(_ value: OrganizationDetail) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 18) {
                    RemoteArtwork(url: container.imageURL(path: value.logoPath, kind: .profile), kind: .profile)
                        .frame(width: 150, height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.cornerRadius))
                    VStack(alignment: .leading) {
                        Text(value.name).font(.system(.largeTitle, design: .serif, weight: .black))
                        if let country = value.originCountry { Text(country).foregroundStyle(CinemaTheme.muted) }
                    }
                }
                if !value.description.isEmpty { detailSection(String(localized: "About", bundle: .module), text: value.description) }
                titleGrid(CatalogAdultVisibility.titles(value.titles.results, includeAdult: includeAdult))
            }
            .padding(24)
        }
    }

    private func keyword(_ value: KeywordDetail) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                Label(value.name, systemImage: "number")
                    .font(.system(.largeTitle, design: .serif, weight: .black))
                titleGrid(CatalogAdultVisibility.titles(value.titles.results, includeAdult: includeAdult))
            }
            .padding(24)
        }
    }

    private func detailSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title)
            Text(text).foregroundStyle(CinemaTheme.foreground.opacity(0.86)).lineSpacing(4)
        }
    }

    @ViewBuilder
    private func titleShelf(_ title: String, titles: [TitleSummary]) -> some View {
        if !titles.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(titles.prefix(30)) { item in
                            NavigationLink(value: item) { PosterCard(title: item) }
                                .catalogNavigationButtonStyle()
                        }
                    }
                }
            }
        }
    }

    private func titleGrid(_ titles: [TitleSummary]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 18)], spacing: 24) {
            ForEach(titles) { item in
                NavigationLink(value: item) { PosterCard(title: item) }
                    .catalogNavigationButtonStyle()
            }
        }
    }

}

public struct SeasonDetailView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.locale) private var locale
    @State private var state: Loadable<SeasonDetail> = .idle
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
                        ForEach(detail.episodes) { episode in
                            NavigationLink(value: EpisodeRoute(
                                series: route.series,
                                seasonNumber: detail.seasonNumber,
                                episode: episode
                            )) {
                                EpisodeRow(episode: episode)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(24)
                }
            }
        }
        .navigationTitle(route.season.name)
        .cinemaScreen()
        .task { await load() }
    }

    private func load() async {
        guard case .idle = state, let catalog = container.catalog as? any CatalogV2Repository else { return }
        state = .loading
        do {
            state = .loaded(try await catalog.season(
                seriesID: route.seriesID,
                number: route.season.seasonNumber,
                language: LocaleResolver.tmdbLanguage(for: locale)
            ))
        } catch { state = .failed(error.localizedDescription) }
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
    @State private var accountRating: Double?
    @State private var ratingMessage: String?
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
                        CatalogMediaSection(images: detail.images, videos: detail.videos)
                        CreditShelf(title: String(localized: "Guest stars", bundle: .module), credits: detail.guestStars)
                        CreditShelf(title: String(localized: "Crew", bundle: .module), credits: detail.crew)
                        if case .signedIn = container.accountSession.state {
                            Menu {
                                AccountRatingOptions(currentRating: accountRating) { value in
                                    Task { await setRating(value, detail: detail) }
                                }
                            } label: {
                                Label(
                                    accountRating.map { String(format: "%.1f", $0) } ?? String(localized: "Rate episode", bundle: .module),
                                    systemImage: accountRating == nil ? "star" : "star.fill"
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(CinemaTheme.accent)
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
        .onDisappear {
            container.watchRemoteSession?.clear(contextKey: "episode:\(route.episode.episodeKey)")
        }
        .alert(String(localized: "Rating", bundle: .module), isPresented: Binding(
            get: { ratingMessage != nil },
            set: { if !$0 { ratingMessage = nil } }
        )) { Button(String(localized: "OK", bundle: .module), role: .cancel) {} } message: { Text(ratingMessage ?? "") }
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
            syncWatchRemote(detail)
            if let pending = await container.pendingEpisodeRating(
                seriesID: detail.seriesId,
                seasonNumber: detail.seasonNumber,
                episodeNumber: detail.episodeNumber
            ) {
                accountRating = pending.value
            }
        } catch { state = .failed(error.localizedDescription) }
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

    @MainActor
    private func setRating(_ value: Double?, detail: EpisodeDetail) async {
        do {
            _ = try await container.queueEpisodeRating(
                seriesID: detail.seriesId,
                seasonNumber: detail.seasonNumber,
                episodeNumber: detail.episodeNumber,
                value: value
            )
            accountRating = value
            _ = await container.flushAccountOutbox()
        } catch {
            ratingMessage = error.localizedDescription
        }
    }
}
