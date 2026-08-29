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
