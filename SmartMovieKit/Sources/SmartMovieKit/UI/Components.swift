import SwiftUI

public struct RemoteArtwork: View {
    private let url: URL?
    private let kind: ImageKind
    private let contentMode: ContentMode

    public init(url: URL?, kind: ImageKind, contentMode: ContentMode = .fill) {
        self.url = url
        self.kind = kind
        self.contentMode = contentMode
    }

    public var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
            ArtworkContent(phase: phase, kind: kind, contentMode: contentMode, isLoading: url != nil)
        }
    }
}

struct ArtworkContent: View {
    let phase: AsyncImagePhase
    let kind: ImageKind
    let contentMode: ContentMode
    let isLoading: Bool

    var body: some View {
        // The viewport, not the downloaded image's aspect ratio, owns layout.
        // Otherwise a wide backdrop expands a compact hero after loading.
        Color.clear.overlay {
            switch phase {
            case .empty:
                if isLoading {
                    LoadingPlaceholder()
                } else {
                    unavailableArtwork
                }
            case .success(let image):
                image.resizable().aspectRatio(contentMode: contentMode)
            case .failure:
                unavailableArtwork
            @unknown default:
                CinemaTheme.elevated
            }
        }
        .clipped()
    }

    private var unavailableArtwork: some View {
        ZStack {
            CinemaTheme.elevated
            Image(systemName: kind == .profile ? "person.crop.circle" : "film.stack")
                .font(.largeTitle)
                .foregroundStyle(CinemaTheme.muted)
        }
    }
}

public struct PosterCard: View {
    @Environment(AppContainer.self) private var container
    private let title: TitleSummary
    private let width: CGFloat

    public init(title: TitleSummary, width: CGFloat = 150) {
        self.title = title
        self.width = width
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            RemoteArtwork(url: container.imageURL(path: title.posterPath, kind: .poster), kind: .poster)
                .frame(width: width, height: width * 1.48)
                .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.cornerRadius))
                .overlay(alignment: .bottomTrailing) {
                    RatingBadge(rating: title.voteAverage)
                        .padding(8)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: CinemaTheme.cornerRadius)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.4), radius: 18, y: 10)
            Text(title.displayTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CinemaTheme.foreground)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(String(localized: title.mediaType == .movie ? "MOVIE" : "TV", bundle: .module))
                    .font(.caption2.weight(.black))
                    .tracking(1.1)
                if let year = title.releaseYear {
                    Text("•")
                    Text(year)
                }
            }
            .font(.caption)
            .foregroundStyle(CinemaTheme.muted)
        }
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title.displayTitle)
        .accessibilityValue(String(format: String(localized: "Rating %.1f", bundle: .module), title.voteAverage))
    }
}

public struct CatalogEntityCard: View {
    @Environment(AppContainer.self) private var container
    private let entity: CatalogEntity
    private let width: CGFloat

    public init(entity: CatalogEntity, width: CGFloat = 150) {
        self.entity = entity
        self.width = width
    }

    public var body: some View {
        if case .title(let title) = entity {
            PosterCard(title: title, width: width)
        } else {
            VStack(alignment: .leading, spacing: 9) {
                RemoteArtwork(url: artworkURL, kind: artworkKind)
                    .frame(width: width, height: width * 1.18)
                    .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.cornerRadius))
                    .overlay(alignment: .topLeading) {
                        Text(kindLabel)
                            .font(.caption2.weight(.black))
                            .tracking(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.72), in: Capsule())
                            .padding(8)
                    }
                Text(entity.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CinemaTheme.foreground)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(CinemaTheme.muted)
                    .lineLimit(1)
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
    }

    private var artworkURL: URL? {
        switch entity {
        case .person(let value): container.imageURL(path: value.profilePath, kind: .profile)
        case .collection(let value): container.imageURL(path: value.posterPath ?? value.backdropPath, kind: .poster)
        case .organization(let value): container.imageURL(path: value.logoPath, kind: .profile)
        case .season(let value): container.imageURL(path: value.posterPath, kind: .poster)
        case .episode(let value): container.imageURL(path: value.stillPath, kind: .backdrop)
        case .title, .keyword: nil
        }
    }

    private var artworkKind: ImageKind {
        switch entity {
        case .person, .organization: .profile
        case .episode: .backdrop
        default: .poster
        }
    }

    private var kindLabel: String { entity.kind.rawValue.uppercased() }

    private var subtitle: String {
        switch entity {
        case .person(let value): value.knownForDepartment ?? String(localized: "Person", bundle: .module)
        case .collection: String(localized: "Collection", bundle: .module)
        case .organization(let value): value.originCountry ?? String(localized: "Organization", bundle: .module)
        case .keyword: String(localized: "Keyword", bundle: .module)
        case .season(let value): String(format: String(localized: "%d episodes", bundle: .module), value.episodeCount)
        case .episode(let value): "S\(value.seasonNumber) · E\(value.episodeNumber)"
        case .title: ""
        }
    }
}

public struct TitleRow: View {
    @Environment(AppContainer.self) private var container
    private let title: TitleSummary

    public init(title: TitleSummary) { self.title = title }

    public var body: some View {
        HStack(spacing: 16) {
            RemoteArtwork(url: container.imageURL(path: title.posterPath, kind: .poster), kind: .poster)
                .frame(width: 88, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 8) {
                Text(title.displayTitle)
                    .font(.headline)
                    .foregroundStyle(CinemaTheme.foreground)
                HStack {
                    RatingBadge(rating: title.voteAverage)
                    if let year = title.releaseYear {
                        Text(year).foregroundStyle(CinemaTheme.muted)
                    }
                }
                Text(title.overview)
                    .font(.subheadline)
                    .foregroundStyle(CinemaTheme.muted)
                    .lineLimit(3)
            }
        }
        .padding(12)
        .background(CinemaTheme.surface, in: RoundedRectangle(cornerRadius: CinemaTheme.cornerRadius))
        .accessibilityElement(children: .combine)
    }
}

public struct MediaPicker: View {
    @Binding private var selection: MediaType

    public init(selection: Binding<MediaType>) { _selection = selection }

    public var body: some View {
        Picker(String(localized: "Content type", bundle: .module), selection: $selection) {
            ForEach(MediaType.allCases) { type in
                Text(type.displayName).tag(type)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(String(localized: "Content type", bundle: .module))
    }
}
