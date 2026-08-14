import SwiftUI

public struct HomeView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.locale) private var locale
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var model: HomeViewModel?

    public init() {}

    public var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(String(localized: "SmartMovie", bundle: .module))
        .homeTitleDisplayMode()
        .cinemaScreen()
        .task {
            if model == nil { model = HomeViewModel(catalog: container.catalog) }
            model?.load(language: LocaleResolver.tmdbLanguage(for: locale))
        }
    }

    @ViewBuilder
    private func content(_ model: HomeViewModel) -> some View {
        @Bindable var model = model
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                MediaPicker(selection: $model.mediaType)
                    .frame(maxWidth: 420)
                    .padding(.horizontal)
                    .onChange(of: model.mediaType) {
                        model.load(language: LocaleResolver.tmdbLanguage(for: locale), force: true)
                    }

                switch model.state {
                case .idle, .loading:
                    loadingContent
                case .failed(let message):
                    StateMessageView(
                        icon: "wifi.exclamationmark",
                        title: String(localized: "Unable to load Home", bundle: .module),
                        message: message,
                        retry: { model.load(language: LocaleResolver.tmdbLanguage(for: locale), force: true) }
                    )
                    .frame(minHeight: 420)
                case .loaded(let feed):
                    if let hero = feed.hero { heroView(hero) }
                    ForEach(feed.sections) { section in shelf(section) }
                }
            }
            .padding(.vertical)
        }
        .refreshable {
            model.load(language: LocaleResolver.tmdbLanguage(for: locale), force: true)
        }
    }

    private func heroView(_ title: TitleSummary) -> some View {
        NavigationLink(value: title) {
            ZStack(alignment: .bottomLeading) {
                RemoteArtwork(
                    url: container.imageURL(path: title.backdropPath ?? title.posterPath, kind: .backdrop),
                    kind: .backdrop
                )
                .frame(height: horizontalSizeClass == .regular ? 480 : 390)
                .overlay {
                    LinearGradient(
                        colors: [.clear, CinemaTheme.background.opacity(0.22), CinemaTheme.background],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: title.mediaType == .movie ? "FEATURED FILM" : "FEATURED SERIES", bundle: .module))
                        .font(.caption.weight(.black))
                        .tracking(2)
                        .foregroundStyle(CinemaTheme.accent)
                    Text(title.displayTitle)
                        .font(.system(.largeTitle, design: .serif, weight: .black))
                        .foregroundStyle(CinemaTheme.foreground)
                        .lineLimit(2)
                    HStack {
                        RatingBadge(rating: title.voteAverage)
                        if let year = title.releaseYear {
                            Text(year).foregroundStyle(CinemaTheme.muted)
                        }
                    }
                    Text(title.overview)
                        .font(.body)
                        .foregroundStyle(CinemaTheme.foreground.opacity(0.82))
                        .lineLimit(3)
                        .frame(maxWidth: 620, alignment: .leading)
                    Label(String(localized: "View details", bundle: .module), systemImage: "play.fill")
                        .font(.headline)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(CinemaTheme.accent, in: Capsule())
                        .foregroundStyle(.white)
                }
                .padding(24)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay {
                RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.1), lineWidth: 1)
            }
            .padding(.horizontal)
        }
        .catalogNavigationButtonStyle()
        .accessibilityLabel(title.displayTitle)
        .accessibilityHint(String(localized: "Open title details", bundle: .module))
    }

    private func shelf(_ section: HomeSection) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(section.title).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(section.items) { title in
                        NavigationLink(value: title) {
                            PosterCard(title: title, width: horizontalSizeClass == .regular ? 180 : 148)
                        }
                        .catalogNavigationButtonStyle()
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 18)
            }
        }
    }

    private var loadingContent: some View {
        VStack(spacing: 28) {
            LoadingPlaceholder().frame(height: 390).padding(.horizontal)
            ForEach(0 ..< 2, id: \.self) { _ in
                HStack(spacing: 16) {
                    ForEach(0 ..< 3, id: \.self) { _ in
                        LoadingPlaceholder().frame(width: 148, height: 260)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}
