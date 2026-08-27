import SwiftUI

struct EpisodeRow: View {
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

enum EntityState {
    case loading
    case failed(String)
    case person(PersonDetail)
    case collection(CollectionDetail)
    case organization(OrganizationDetail)
    case keyword(KeywordDetail)
}
