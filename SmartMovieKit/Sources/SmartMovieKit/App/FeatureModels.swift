import Foundation
import Observation

@MainActor
@Observable
public final class HomeViewModel {
    public var mediaType: MediaType = .movie
    public private(set) var state: Loadable<HomeFeed> = .idle
    private let catalog: any CatalogRepository
    private var loadTask: Task<Void, Never>?

    public init(catalog: any CatalogRepository) {
        self.catalog = catalog
    }

    public func load(language: String, force: Bool = false) {
        if !force, case .loaded(let feed) = state, feed.mediaType == mediaType { return }
        loadTask?.cancel()
        state = .loading
        let selectedType = mediaType
        loadTask = Task { [weak self, catalog] in
            do {
                let feed = try await catalog.home(mediaType: selectedType, language: language)
                guard !Task.isCancelled, self?.mediaType == selectedType else { return }
                self?.state = .loaded(feed)
            } catch is CancellationError {
                return
            } catch {
                self?.state = .failed(error.localizedDescription)
            }
        }
    }
}

@MainActor
@Observable
public final class ExploreViewModel {
    public var mediaType: MediaType = .movie
    public var filter = DiscoverFilter()
    public var layout: CatalogLayout = .grid
    public private(set) var genres: [Genre] = []
    public private(set) var items: [TitleSummary] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var canLoadMore = true
    private let catalog: any CatalogRepository
    private var page = 0
    private var task: Task<Void, Never>?

    public init(catalog: any CatalogRepository) {
        self.catalog = catalog
    }

    public func reload(language: String) {
        task?.cancel()
        items = []
        page = 0
        canLoadMore = true
        errorMessage = nil
        task = Task { [weak self, catalog] in
            guard let self else { return }
            isLoading = true
            defer { isLoading = false }
            do {
                async let genreRequest = catalog.genres(mediaType: mediaType, language: language)
                async let pageRequest = catalog.discover(
                    mediaType: mediaType,
                    filter: filter,
                    page: 1,
                    language: language
                )
                let (loadedGenres, result) = try await (genreRequest, pageRequest)
                guard !Task.isCancelled else { return }
                genres = loadedGenres
                items = result.results
                page = result.page
                canLoadMore = result.page < result.totalPages
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func loadMoreIfNeeded(current item: TitleSummary, language: String) {
        guard item.id == items.last?.id, canLoadMore, !isLoading else { return }
        let nextPage = page + 1
        isLoading = true
        Task { [weak self, catalog] in
            guard let self else { return }
            defer { isLoading = false }
            do {
                let result = try await catalog.discover(
                    mediaType: mediaType,
                    filter: filter,
                    page: nextPage,
                    language: language
                )
                items.append(contentsOf: result.results.filter { incoming in
                    !items.contains(where: { $0.libraryKey == incoming.libraryKey })
                })
                page = result.page
                canLoadMore = result.page < result.totalPages
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

public enum CatalogLayout: String, CaseIterable, Identifiable {
    case grid
    case list
    public var id: String { rawValue }
}

@MainActor
@Observable
public final class SearchViewModel {
    public var query = ""
    public private(set) var mode: CatalogSearchMode = .catalog
    public var scope: SearchScope = .all
    public var entityScope: SearchScopeV2 = .all
    public var externalIDSource: ExternalIDSource = .imdb
    public private(set) var entities: [CatalogEntity] = []
    public var items: [TitleSummary] {
        entities.compactMap { entity in
            if case .title(let title) = entity { return title }
            return nil
        }
    }
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var canLoadMore = false
    public private(set) var hasSubmittedExternalID = false
    private let catalog: any CatalogRepository
    private var page = 0
    private var searchTask: Task<Void, Never>?

    public init(catalog: any CatalogRepository) {
        self.catalog = catalog
    }

    public func setMode(_ mode: CatalogSearchMode) {
        guard self.mode != mode else { return }
        searchTask?.cancel()
        self.mode = mode
        query = ""
        entities = []
        errorMessage = nil
        isLoading = false
        canLoadMore = false
        hasSubmittedExternalID = false
        page = 0
    }

    public func resetExternalIDResults() {
        guard mode == .externalID else { return }
        searchTask?.cancel()
        entities = []
        errorMessage = nil
        isLoading = false
        hasSubmittedExternalID = false
    }

    public func scheduleSearch(language: String, region: String? = nil, includeAdult: Bool = false) {
        searchTask?.cancel()
        guard mode == .catalog else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            entities = []
            errorMessage = nil
            isLoading = false
            page = 0
            return
        }
        let expectedQuery = trimmed
        let expectedScope = scope
        let expectedEntityScope = entityScope
        searchTask = Task { [weak self, catalog] in
            do {
                try await Task.sleep(for: .milliseconds(350))
                guard let self else { return }
                isLoading = true
                errorMessage = nil
                let result: PagedResult<CatalogEntity>
                if let catalogV2 = catalog as? any CatalogV2Repository {
                    result = try await catalogV2.searchEntities(EntitySearchRequest(
                        query: expectedQuery,
                        scope: expectedEntityScope,
                        context: CatalogPageContext(
                            page: 1,
                            language: language,
                            region: region,
                            includeAdult: includeAdult
                        )
                    ))
                } else {
                    let legacy = try await catalog.search(
                        query: expectedQuery,
                        scope: expectedScope,
                        page: 1,
                        language: language
                    )
                    result = PagedResult(
                        page: legacy.page,
                        totalPages: legacy.totalPages,
                        results: legacy.results.map(CatalogEntity.title)
                    )
                }
                guard !Task.isCancelled,
                      query.trimmingCharacters(in: .whitespacesAndNewlines) == expectedQuery,
                      scope == expectedScope,
                      entityScope == expectedEntityScope else { return }
                entities = result.results
                page = result.page
                canLoadMore = result.page < result.totalPages
                isLoading = false
            } catch is CancellationError {
                return
            } catch {
                self?.isLoading = false
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    public func findExternalID(language: String) {
        searchTask?.cancel()
        let externalID = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mode == .externalID, !externalID.isEmpty else {
            entities = []
            errorMessage = nil
            isLoading = false
            return
        }
        hasSubmittedExternalID = true
        let expectedSource = externalIDSource
        searchTask = Task { [weak self, catalog] in
            guard let self else { return }
            isLoading = true
            errorMessage = nil
            canLoadMore = false
            do {
                guard let catalogV2 = catalog as? any CatalogV2Repository else { throw APIError.notFound }
                let result = try await catalogV2.findExternalID(
                    externalID,
                    source: expectedSource,
                    language: language
                )
                guard !Task.isCancelled,
                      mode == .externalID,
                      query.trimmingCharacters(in: .whitespacesAndNewlines) == externalID,
                      externalIDSource == expectedSource else { return }
                entities = result.results
                isLoading = false
            } catch is CancellationError {
                return
            } catch {
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    public func loadMoreIfNeeded(
        current item: TitleSummary,
        language: String,
        region: String? = nil,
        includeAdult: Bool = false
    ) {
        loadMoreIfNeeded(currentID: item.libraryKey, language: language, region: region, includeAdult: includeAdult)
    }

    public func loadMoreIfNeeded(
        current entity: CatalogEntity,
        language: String,
        region: String? = nil,
        includeAdult: Bool = false
    ) {
        loadMoreIfNeeded(currentID: entity.id, language: language, region: region, includeAdult: includeAdult)
    }

    private func loadMoreIfNeeded(currentID: String, language: String, region: String?, includeAdult: Bool) {
        guard mode == .catalog, currentID == entities.last?.id, canLoadMore, !isLoading else { return }
        let expectedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedScope = scope
        let expectedEntityScope = entityScope
        let nextPage = page + 1
        isLoading = true
        Task { [weak self, catalog] in
            guard let self else { return }
            defer { isLoading = false }
            do {
                let result: PagedResult<CatalogEntity>
                if let catalogV2 = catalog as? any CatalogV2Repository {
                    result = try await catalogV2.searchEntities(EntitySearchRequest(
                        query: expectedQuery,
                        scope: expectedEntityScope,
                        context: CatalogPageContext(
                            page: nextPage,
                            language: language,
                            region: region,
                            includeAdult: includeAdult
                        )
                    ))
                } else {
                    let legacy = try await catalog.search(
                        query: expectedQuery,
                        scope: expectedScope,
                        page: nextPage,
                        language: language
                    )
                    result = PagedResult(
                        page: legacy.page,
                        totalPages: legacy.totalPages,
                        results: legacy.results.map(CatalogEntity.title)
                    )
                }
                guard query.trimmingCharacters(in: .whitespacesAndNewlines) == expectedQuery,
                      scope == expectedScope,
                      entityScope == expectedEntityScope else { return }
                entities.append(contentsOf: result.results.filter { incoming in
                    !entities.contains(where: { $0.id == incoming.id })
                })
                page = result.page
                canLoadMore = result.page < result.totalPages
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

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

@MainActor
@Observable
public final class LibraryViewModel {
    public var collection: LibraryCollection = .favorites
    public var mediaType: MediaType?
    public var sort: LibrarySort = .recentlyAdded
    public private(set) var items: [LibrarySnapshot] = []
    public private(set) var errorMessage: String?
    private let library: any LibraryRepository

    public init(library: any LibraryRepository) {
        self.library = library
    }

    public func reload() {
        do {
            items = try library.items(in: collection, mediaType: mediaType, sort: sort)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
