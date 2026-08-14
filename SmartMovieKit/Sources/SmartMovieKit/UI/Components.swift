import SwiftUI

public struct RemoteArtwork: View {
    private let url: URL?
    private let kind: ImageKind

    public init(url: URL?, kind: ImageKind) {
        self.url = url
        self.kind = kind
    }

    public var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
            switch phase {
            case .empty:
                LoadingPlaceholder()
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                ZStack {
                    CinemaTheme.elevated
                    Image(systemName: kind == .profile ? "person.crop.circle" : "film.stack")
                        .font(.largeTitle)
                        .foregroundStyle(CinemaTheme.muted)
                }
            @unknown default:
                CinemaTheme.elevated
            }
        }
        .clipped()
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
