import SwiftUI

public struct DetailView: View {
    @Environment(AppContainer.self) var container
    @Environment(\.locale) var locale
    @Environment(\.openURL) var openURL
    #if os(macOS) || os(visionOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: DetailViewModel?
    @State private var trailerStatus: String?
    @State private var didAutoplayTrailer = false
    @State private var accountRating: Double?
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
            await model?.load(
                language: LocaleResolver.tmdbLanguage(for: locale),
                region: container.regionSettings.effectiveRegion,
                includeAdult: container.adultContent.includeAdult
            )
            guard let model else { return }
            if case .signedIn = container.accountSession.state { await loadAccountRating() }
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
                    Task {
                        await model.load(
                            language: LocaleResolver.tmdbLanguage(for: locale),
                            region: container.regionSettings.effectiveRegion,
                            includeAdult: container.adultContent.includeAdult
                        )
                    }
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
                if let deep = model.deepDetail { deepSections(deep) }
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

                heroActions(model)
            }
            .padding(24)
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: model.isFavorite)
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: model.isWatchlisted)
    }

    private func heroActions(_ model: DetailViewModel) -> some View {
        HStack(spacing: 12) {
            ActionPill(
                title: String(localized: "Trailer", bundle: .module),
                systemImage: "play.fill",
                prominent: true
            ) {
                playTrailer(model)
            }
            .disabled(model.preferredTrailer(language: LocaleResolver.tmdbLanguage(for: locale)) == nil)

            libraryAction(model, collection: .favorites)
            libraryAction(model, collection: .watchlist)
            if case .signedIn = container.accountSession.state { ratingMenu }
        }
    }

    private func libraryAction(_ model: DetailViewModel, collection: LibraryCollection) -> some View {
        let selected = collection == .favorites ? model.isFavorite : model.isWatchlisted
        let title = collection == .favorites
            ? String(localized: "Favorite", bundle: .module)
            : String(localized: "Watchlist", bundle: .module)
        let image = collection == .favorites ? "heart" : "bookmark"
        return ActionPill(
            title: title,
            systemImage: selected ? "\(image).fill" : image,
            prominent: false
        ) {
            model.toggle(collection)
            syncWatchRemote(model)
            Task { await container.flushLibraryOutbox() }
        }
    }

    private var ratingMenu: some View {
        Menu {
            ForEach(1...10, id: \.self) { value in
                Button("\(value) / 10") { Task { await setAccountRating(Double(value)) } }
            }
            if accountRating != nil {
                Button(String(localized: "Remove rating", bundle: .module), role: .destructive) {
                    Task { await setAccountRating(nil) }
                }
            }
        } label: {
            Label(
                accountRating.map { String(format: "%.1f", $0) } ?? String(localized: "Rate", bundle: .module),
                systemImage: accountRating == nil ? "star" : "star.fill"
            )
            .font(.subheadline.weight(.bold))
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(CinemaTheme.surface, in: Capsule())
        }
        .foregroundStyle(CinemaTheme.foreground)
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
        guard !model.containsAdultContent else { return }
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

    @MainActor
    private func loadAccountRating() async {
        if let state = try? await container.account.accountState(mediaType: summary.mediaType, id: summary.id) {
            accountRating = state.rated.ratingValue
        }
        if let pending = await container.pendingTitleRating(mediaType: summary.mediaType, mediaID: summary.id) {
            accountRating = pending.value
        }
    }

    @MainActor
    private func setAccountRating(_ value: Double?) async {
        do {
            _ = try await container.queueTitleRating(
                mediaType: summary.mediaType,
                mediaID: summary.id,
                value: value
            )
            accountRating = value
            _ = await container.flushAccountOutbox()
        } catch {
            trailerStatus = error.localizedDescription
        }
    }
}

private extension JSONValue {
    var ratingValue: Double? {
        guard case .object(let values) = self,
              let rawValue = values["value"],
              case .number(let value) = rawValue else { return nil }
        return value
    }
}
