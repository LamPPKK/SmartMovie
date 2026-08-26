import Foundation
import Observation

@MainActor
@Observable
public final class DetailViewModel {
    public private(set) var state: Loadable<TitleDetail> = .idle
    public private(set) var deepDetail: TitleDetailV2?
    public private(set) var isFavorite = false
    public private(set) var isWatchlisted = false
    private let summary: TitleSummary
    private let catalog: any CatalogRepository
    private let library: any LibraryRepository

    public init(summary: TitleSummary, catalog: any CatalogRepository, library: any LibraryRepository) {
        self.summary = summary
        self.catalog = catalog
        self.library = library
        refreshLibraryState()
    }

    public func load(language: String, region: String? = nil, includeAdult: Bool = false) async {
        if case .loaded = state { return }
        state = .loading
        do {
            if let catalogV2 = catalog as? any CatalogV2Repository {
                let detail = try await catalogV2.deepDetail(
                    mediaType: summary.mediaType,
                    id: summary.id,
                    language: language,
                    region: region,
                    includeAdult: includeAdult
                )
                deepDetail = detail
                state = .loaded(detail.legacy)
            } else {
                state = .loaded(try await catalog.detail(mediaType: summary.mediaType, id: summary.id, language: language))
            }
        } catch is CancellationError {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func toggle(_ collection: LibraryCollection) {
        do {
            let currentSummary = deepDetail?.summary ?? {
                if case .loaded(let detail) = state { return detail.summary }
                return summary
            }()
            try library.toggle(currentSummary, in: collection)
            refreshLibraryState(using: currentSummary)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func preferredTrailer(language: String) -> Video? {
        guard case .loaded(let detail) = state else { return nil }
        let videos = deepDetail?.videos ?? detail.videos
        let youtube = videos.filter { $0.site.caseInsensitiveCompare("YouTube") == .orderedSame }
        let trailers = youtube.filter { $0.type.caseInsensitiveCompare("Trailer") == .orderedSame }
        return trailers.first(where: { $0.official && ($0.language == language || language.hasPrefix($0.language ?? "-")) })
            ?? trailers.first
            ?? youtube.first(where: { $0.type.caseInsensitiveCompare("Teaser") == .orderedSame })
    }

    public func refreshLibraryState(using value: TitleSummary? = nil) {
        let title = value ?? deepDetail?.summary ?? summary
        do {
            isFavorite = try library.contains(title, in: .favorites)
            isWatchlisted = try library.contains(title, in: .watchlist)
        } catch {
            isFavorite = false
            isWatchlisted = false
        }
    }

    public var containsAdultContent: Bool { deepDetail?.adult ?? summary.isAdult }
}
