import SwiftUI

enum CatalogMediaPresentation {
    static func images(_ values: [ImageAsset], limit: Int = 20) -> [ImageAsset] {
        unique(values, limit: limit, key: \ImageAsset.filePath)
    }

    static func videos(_ values: [Video], limit: Int = 12) -> [Video] {
        unique(
            values.filter {
                $0.site.caseInsensitiveCompare("YouTube") == .orderedSame
                    && !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            },
            limit: limit,
            key: \Video.key
        )
    }

    static func externalIdentifiers(_ values: [String: String], limit: Int = 8) -> [(String, String)] {
        values
            .filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.key < $1.key }
            .prefix(limit)
            .map { ($0.key, $0.value) }
    }

    static func videoURL(for video: Video) -> URL? {
        guard videos([video]).isEmpty == false else { return nil }
        #if os(tvOS)
        return URL(string: "youtube://watch?v=\(video.key)")
        #else
        var components = URLComponents(string: "https://www.youtube.com/watch")
        components?.queryItems = [URLQueryItem(name: "v", value: video.key)]
        return components?.url
        #endif
    }

    private static func unique<Value>(
        _ values: [Value],
        limit: Int,
        key: KeyPath<Value, String>
    ) -> [Value] {
        var seen = Set<String>()
        return values.filter { value in
            let identifier = value[keyPath: key].trimmingCharacters(in: .whitespacesAndNewlines)
            return !identifier.isEmpty && seen.insert(identifier).inserted
        }
        .prefix(limit)
        .map(\.self)
    }
}

struct CatalogMediaSection: View {
    private struct ArtworkPresentation {
        let kind: ImageKind
        let contentMode: ContentMode
        let width: CGFloat
        let height: CGFloat
    }

    @Environment(AppContainer.self) private var container
    @Environment(\.openURL) private var openURL

    let images: [ImageAsset]
    let videos: [Video]

    private var presentedImages: [ImageAsset] {
        CatalogMediaPresentation.images(images)
    }

    private var presentedVideos: [Video] {
        CatalogMediaPresentation.videos(videos)
    }

    var body: some View {
        if !presentedImages.isEmpty || !presentedVideos.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                imageGallery
                videoGallery
            }
        }
    }

    @ViewBuilder
    private var imageGallery: some View {
        if !presentedImages.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(String(localized: "Images", bundle: .module))
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(presentedImages, id: \.filePath) { asset in
                            let presentation = presentation(for: asset)
                            RemoteArtwork(
                                url: container.imageURL(path: asset.filePath, kind: presentation.kind),
                                kind: presentation.kind,
                                contentMode: presentation.contentMode
                            )
                            .frame(width: presentation.width, height: presentation.height)
                            .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.cornerRadius))
                            .overlay {
                                RoundedRectangle(cornerRadius: CinemaTheme.cornerRadius)
                                    .stroke(.white.opacity(0.08), lineWidth: 1)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(String(localized: "Catalog image", bundle: .module))
                            #if os(tvOS)
                            .focusable()
                            #endif
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var videoGallery: some View {
        if !presentedVideos.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(String(localized: "Videos", bundle: .module))
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(presentedVideos) { video in
                            Button {
                                guard let url = CatalogMediaPresentation.videoURL(for: video) else { return }
                                openURL(url)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "play.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(CinemaTheme.accent)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(video.name)
                                            .font(.subheadline.weight(.bold))
                                            .lineLimit(2)
                                        Text(video.type)
                                            .font(.caption)
                                            .foregroundStyle(CinemaTheme.muted)
                                    }
                                }
                                .frame(width: 230, alignment: .leading)
                                .padding(14)
                                .background(CinemaTheme.surface, in: RoundedRectangle(cornerRadius: CinemaTheme.cornerRadius))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func presentation(for asset: ImageAsset) -> ArtworkPresentation {
        if asset.kind.caseInsensitiveCompare("poster") == .orderedSame {
            return ArtworkPresentation(kind: .poster, contentMode: .fill, width: 140, height: 210)
        }
        let isLogo = asset.kind.caseInsensitiveCompare("logo") == .orderedSame
        return ArtworkPresentation(
            kind: .backdrop,
            contentMode: isLogo ? .fit : .fill,
            width: 240,
            height: 135
        )
    }
}

struct CatalogMetadataSection: View {
    let values: [(label: String, value: String)]
    let externalIDs: [String: String]

    private var identifiers: [(String, String)] {
        CatalogMediaPresentation.externalIdentifiers(externalIDs)
    }

    var body: some View {
        if !values.isEmpty || !identifiers.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(String(localized: "Details", bundle: .module))
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    LabeledContent(value.label, value: value.value)
                }
                if !identifiers.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(String(localized: "External identifiers", bundle: .module))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(CinemaTheme.foreground)
                        ForEach(identifiers, id: \.0) { identifier in
                            Text("\(identifier.0): \(identifier.1)")
                                .font(.subheadline)
                        }
                    }
                }
            }
            .foregroundStyle(CinemaTheme.muted)
        }
    }
}
