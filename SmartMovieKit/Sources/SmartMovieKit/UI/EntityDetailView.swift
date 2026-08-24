import SwiftUI

public struct SeasonRoute: Hashable, Sendable {
    public let seriesID: Int
    public let season: SeasonSummary

    public init(seriesID: Int, season: SeasonSummary) {
        self.seriesID = seriesID
        self.season = season
    }
}

public struct EpisodeRoute: Hashable, Sendable {
    public let seriesID: Int
    public let seasonNumber: Int
    public let episode: EpisodeSummary

    public init(seriesID: Int, seasonNumber: Int, episode: EpisodeSummary) {
        self.seriesID = seriesID
        self.seasonNumber = seasonNumber
        self.episode = episode
    }
}

public struct EntityDetailView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.locale) private var locale
    @State private var state: EntityState = .loading
    private let entity: CatalogEntity

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
        .task(id: entity.id) { await load() }
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
            case .person(let value): state = .person(try await catalog.person(id: value.id, language: language))
            case .collection(let value): state = .collection(try await catalog.collection(id: value.id, language: language))
            case .organization(let value):
                state = .organization(try await catalog.organization(kind: value.entityKind, id: value.id, language: language, page: 1))
            case .keyword(let value): state = .keyword(try await catalog.keyword(id: value.id, language: language, page: 1))
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
                titleShelf(String(localized: "Known for", bundle: .module), titles: value.knownFor)
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
                titleGrid(value.parts)
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
                titleGrid(value.titles.results)
            }
            .padding(24)
        }
    }

    private func keyword(_ value: KeywordDetail) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                Label(value.name, systemImage: "number")
                    .font(.system(.largeTitle, design: .serif, weight: .black))
                titleGrid(value.titles.results)
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
                        Text(detail.name).font(.system(.largeTitle, design: .serif, weight: .black))
                        if !detail.overview.isEmpty { Text(detail.overview).foregroundStyle(CinemaTheme.muted) }
                        CreditShelf(title: String(localized: "Cast", bundle: .module), credits: detail.credits.cast)
                        CreditShelf(title: String(localized: "Crew", bundle: .module), credits: detail.credits.crew)
                        ForEach(detail.episodes) { episode in
                            NavigationLink(value: EpisodeRoute(
                                seriesID: route.seriesID,
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
                        if let date = detail.airDate { Text(date).foregroundStyle(CinemaTheme.muted) }
                        Text(detail.overview.isEmpty ? String(localized: "No overview is available.", bundle: .module) : detail.overview)
                            .lineSpacing(4)
                        CreditShelf(title: String(localized: "Guest stars", bundle: .module), credits: detail.guestStars)
                        CreditShelf(title: String(localized: "Crew", bundle: .module), credits: detail.crew)
                        if case .signedIn = container.accountSession.state {
                            Menu {
                                ForEach(1...10, id: \.self) { value in
                                    Button("\(value) / 10") { Task { await setRating(Double(value), detail: detail) } }
                                }
                                if accountRating != nil {
                                    Button(String(localized: "Remove rating", bundle: .module), role: .destructive) {
                                        Task { await setRating(nil, detail: detail) }
                                    }
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
            if let pending = await container.pendingEpisodeRating(
                seriesID: detail.seriesId,
                seasonNumber: detail.seasonNumber,
                episodeNumber: detail.episodeNumber
            ) {
                accountRating = pending.value
            }
        } catch { state = .failed(error.localizedDescription) }
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

private struct EpisodeRow: View {
    @Environment(AppContainer.self) private var container
    let episode: EpisodeSummary

    var body: some View {
        HStack(spacing: 16) {
            RemoteArtwork(url: container.imageURL(path: episode.stillPath, kind: .backdrop), kind: .backdrop)
                .frame(width: 180, height: 102)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 7) {
                Text("E\(episode.episodeNumber) · \(episode.name)").font(.headline)
                Text(episode.overview).font(.subheadline).foregroundStyle(CinemaTheme.muted).lineLimit(3)
            }
        }
        .padding(12)
        .background(CinemaTheme.surface, in: RoundedRectangle(cornerRadius: CinemaTheme.cornerRadius))
    }
}

private enum EntityState {
    case loading
    case failed(String)
    case person(PersonDetail)
    case collection(CollectionDetail)
    case organization(OrganizationDetail)
    case keyword(KeywordDetail)
}
