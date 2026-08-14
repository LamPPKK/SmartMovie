import SwiftUI

public struct DetailView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    #if os(macOS) || os(visionOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: DetailViewModel?
    @State private var trailerStatus: String?
    @State private var didAutoplayTrailer = false
    private let summary: TitleSummary
    private let autoplayTrailer: Bool

    public init(summary: TitleSummary, autoplayTrailer: Bool = false) {
        self.summary = summary
        self.autoplayTrailer = autoplayTrailer
    }

    public var body: some View {
        Group {
            if let model { content(model) } else { ProgressView() }
        }
        .inlineNavigationTitle()
        .toolbar {
            #if os(macOS) || os(visionOS)
            Button {
                openWindow(value: summary)
            } label: {
                Label(String(localized: "Open in New Window", bundle: .module), systemImage: "macwindow.badge.plus")
            }
            #endif
        }
        .cinemaScreen()
        .alert(
            String(localized: "Trailer unavailable", bundle: .module),
            isPresented: Binding(
                get: { trailerStatus != nil },
                set: { if !$0 { trailerStatus = nil } }
            )
        ) {
            Button(String(localized: "OK", bundle: .module), role: .cancel) {}
        } message: {
            Text(trailerStatus ?? "")
        }
        .task {
            if model == nil {
                model = DetailViewModel(summary: summary, catalog: container.catalog, library: container.library)
            }
            await model?.load(language: LocaleResolver.tmdbLanguage(for: locale))
            guard let model else { return }
            syncWatchRemote(model)
            if autoplayTrailer, !didAutoplayTrailer {
                didAutoplayTrailer = true
                playTrailer(model)
            }
        }
        .onChange(of: container.watchRemoteCoordinator.libraryRevision) {
            guard let model else { return }
            model.refreshLibraryState()
            syncWatchRemote(model)
        }
    }

    @ViewBuilder
    private func content(_ model: DetailViewModel) -> some View {
        switch model.state {
        case .idle, .loading:
            ScrollView {
                VStack(spacing: 18) {
                    LoadingPlaceholder().frame(height: 430)
                    LoadingPlaceholder().frame(height: 140)
                }
                .padding()
            }
        case .failed(let message):
            StateMessageView(
                icon: "film.stack",
                title: String(localized: "Details unavailable", bundle: .module),
                message: message,
                retry: {
                    Task { await model.load(language: LocaleResolver.tmdbLanguage(for: locale)) }
                }
            )
        case .loaded(let detail):
            detailContent(detail, model: model)
        }
    }

    private func detailContent(_ detail: TitleDetail, model: DetailViewModel) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                hero(detail, model: model)
                overview(detail)
                if !detail.cast.isEmpty { castShelf(detail.cast) }
                if !detail.similar.isEmpty { similarShelf(detail.similar) }
                credits
            }
            .padding(.bottom, 40)
        }
        .navigationTitle(detail.title)
    }

    private func hero(_ detail: TitleDetail, model: DetailViewModel) -> some View {
        ZStack(alignment: .bottom) {
            RemoteArtwork(
                url: container.imageURL(path: detail.backdropPath ?? detail.posterPath, kind: .backdrop),
                kind: .backdrop
            )
            .frame(height: 480)
            .overlay {
                LinearGradient(
                    colors: [.black.opacity(0.05), CinemaTheme.background.opacity(0.45), CinemaTheme.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            VStack(alignment: .leading, spacing: 14) {
                Text(String(localized: detail.mediaType == .movie ? "FEATURE FILM" : "SERIES", bundle: .module))
                    .font(.caption.weight(.black))
                    .tracking(2)
                    .foregroundStyle(CinemaTheme.accent)
                Text(detail.title)
                    .font(.system(.largeTitle, design: .serif, weight: .black))
                    .foregroundStyle(CinemaTheme.foreground)
                HStack(spacing: 12) {
                    RatingBadge(rating: detail.voteAverage)
                    if let year = detail.releaseDate?.prefix(4) { Text(String(year)) }
                    if let runtime = detail.runtimeMinutes { Text(runtimeText(runtime)) }
                    if let seasons = detail.numberOfSeasons {
                        Text(String(format: String(localized: "%d seasons", bundle: .module), seasons))
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CinemaTheme.muted)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(detail.genres) { genre in
                            Text(genre.name)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(CinemaTheme.surface, in: Capsule())
                        }
                    }
                }

                HStack(spacing: 12) {
                    ActionPill(
                        title: String(localized: "Trailer", bundle: .module),
                        systemImage: "play.fill",
                        prominent: true
                    ) {
                        playTrailer(model)
                    }
                    .disabled(model.preferredTrailer(language: LocaleResolver.tmdbLanguage(for: locale)) == nil)

                    ActionPill(
                        title: String(localized: "Favorite", bundle: .module),
                        systemImage: model.isFavorite ? "heart.fill" : "heart",
                        prominent: false
                    ) {
                        model.toggle(.favorites)
                        syncWatchRemote(model)
                    }

                    ActionPill(
                        title: String(localized: "Watchlist", bundle: .module),
                        systemImage: model.isWatchlisted ? "bookmark.fill" : "bookmark",
                        prominent: false
                    ) {
                        model.toggle(.watchlist)
                        syncWatchRemote(model)
                    }
                }
            }
            .padding(24)
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: model.isFavorite)
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: model.isWatchlisted)
    }

    private func overview(_ detail: TitleDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(String(localized: "Story", bundle: .module))
            Text(detail.overview.isEmpty ? String(localized: "No overview is available.", bundle: .module) : detail.overview)
                .font(.body)
                .foregroundStyle(CinemaTheme.foreground.opacity(0.84))
                .lineSpacing(5)
            if let status = detail.status {
                LabeledContent(String(localized: "Status", bundle: .module), value: status)
                    .foregroundStyle(CinemaTheme.muted)
            }
        }
        .padding(.horizontal, 24)
    }

    private func castShelf(_ cast: [CastMember]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(String(localized: "Cast", bundle: .module)).padding(.horizontal, 24)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(cast.prefix(20)) { member in
                        VStack(spacing: 9) {
                            RemoteArtwork(url: container.imageURL(path: member.profilePath, kind: .profile), kind: .profile)
                                .frame(width: 104, height: 132)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            Text(member.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(CinemaTheme.foreground)
                                .lineLimit(2)
                            if let character = member.character {
                                Text(character)
                                    .font(.caption2)
                                    .foregroundStyle(CinemaTheme.muted)
                                    .lineLimit(2)
                            }
                        }
                        .frame(width: 110)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private func similarShelf(_ similar: [TitleSummary]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(String(localized: "More like this", bundle: .module)).padding(.horizontal, 24)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(similar) { title in
                        NavigationLink(value: title) { PosterCard(title: title) }
                            .catalogNavigationButtonStyle()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
    }

    private var credits: some View {
        NavigationLink {
            AboutView()
        } label: {
            Label(String(localized: "About & Credits", bundle: .module), systemImage: "info.circle")
                .foregroundStyle(CinemaTheme.muted)
                .padding(.horizontal, 24)
        }
    }

    private func runtimeText(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remaining = minutes % 60
        return hours > 0 ? "\(hours)h \(remaining)m" : "\(remaining)m"
    }

    private func playTrailer(_ model: DetailViewModel) {
        guard let trailer = model.preferredTrailer(language: LocaleResolver.tmdbLanguage(for: locale)) else {
            trailerStatus = String(localized: "No trailer is available for this title.", bundle: .module)
            return
        }
        #if os(tvOS)
        guard let url = URL(string: "youtube://watch?v=\(trailer.key)") else { return }
        openURL(url) { accepted in
            if !accepted {
                trailerStatus = String(localized: "Install the YouTube app to watch this trailer.", bundle: .module)
            }
        }
        #else
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(trailer.key)") else { return }
        openURL(url)
        #endif
    }

    private func syncWatchRemote(_ model: DetailViewModel) {
        guard case .loaded(let detail) = model.state else { return }
        let language = LocaleResolver.tmdbLanguage(for: locale)
        container.watchRemoteSession?.update(
            context: WatchRemoteContext(
                title: detail.summary,
                artworkURL: container.imageURL(path: detail.posterPath ?? detail.backdropPath, kind: .poster),
                isFavorite: model.isFavorite,
                isWatchlisted: model.isWatchlisted,
                hasTrailer: model.preferredTrailer(language: language) != nil
            )
        )
    }
}

private struct ActionPill: View {
    let title: String
    let systemImage: String
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(prominent ? CinemaTheme.accent : CinemaTheme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(CinemaTheme.foreground)
    }
}

public struct AboutView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "film.stack.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(CinemaTheme.accent)
                Text("SmartMovie")
                    .font(.system(.largeTitle, design: .serif, weight: .black))
                Text(String(localized: "A cinematic place to discover movies and television.", bundle: .module))
                    .foregroundStyle(CinemaTheme.muted)
                Divider().overlay(.white.opacity(0.12))
                Text("TMDB")
                    .font(.title2.bold())
                    .foregroundStyle(Color(red: 0.01, green: 0.71, blue: 0.89))
                Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                    .font(.footnote)
                    .foregroundStyle(CinemaTheme.muted)
                Link("The Movie Database", destination: URL(string: "https://www.themoviedb.org")!)
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(28)
        }
        .navigationTitle(String(localized: "About & Credits", bundle: .module))
        .cinemaScreen()
    }
}
