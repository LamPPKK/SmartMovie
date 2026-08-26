import Foundation
import Observation
@MainActor
@Observable
public final class ExploreViewModel {
    public var mediaType: MediaType = .movie
    public var filter = DiscoverFilter()
    public var draftFilter = DiscoverFilter()
    public var layout: CatalogLayout = .grid
    public private(set) var genres: [Genre] = []
    public private(set) var items: [TitleSummary] = []
    public private(set) var configuration: DiscoverConfiguration?
    public private(set) var advancedDiscoverEnabled = false
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var canLoadMore = true
    private let catalog: any CatalogRepository
    private var page = 0
    private var task: Task<Void, Never>?
    private var configurationTask: Task<Void, Never>?
    private var requestID = UUID()
    private var configurationRequestID = UUID()
    public init(catalog: any CatalogRepository) { self.catalog = catalog }

    public var providers: [WatchProviderOption] {
        configuration?.watchProviders?.values(for: mediaType) ?? []
    }

    @discardableResult
    public func updateCapabilities(_ capabilities: CapabilitiesV2?) -> Bool {
        let enabled = capabilities?.supportsCatalog("advanced_discover") == true
        guard enabled != advancedDiscoverEnabled else { return false }
        advancedDiscoverEnabled = enabled
        configurationTask?.cancel()
        configuration = nil
        if !enabled {
            filter = basicFilter(filter)
            draftFilter = filter
        }
        return true
    }
    @discardableResult
    public func updateContext(region: String, includeAdult: Bool) -> Bool {
        let normalizedRegion = region.uppercased()
        guard filter.region != normalizedRegion || filter.includeAdult != includeAdult else { return false }
        let regionChanged = filter.region != normalizedRegion
        filter.region = normalizedRegion
        filter.includeAdult = includeAdult
        draftFilter.region = normalizedRegion
        draftFilter.includeAdult = includeAdult
        if regionChanged {
            filter.watchProviderIDs.removeAll()
            filter.certificationCountry = normalizedRegion
            filter.certificationMinimum = nil
            filter.certificationMaximum = nil
            draftFilter.watchProviderIDs.removeAll()
            draftFilter.certificationCountry = normalizedRegion
            draftFilter.certificationMinimum = nil
            draftFilter.certificationMaximum = nil
            configuration = nil
        }
        if !advancedDiscoverEnabled {
            filter = basicFilter(filter)
            draftFilter = basicFilter(draftFilter)
        }
        return true
    }

    public func resetFilter() {
        filter = DiscoverFilter(
            certificationCountry: advancedDiscoverEnabled ? filter.region : nil,
            region: filter.region,
            includeAdult: filter.includeAdult
        )
        draftFilter = filter
    }

    public func beginEditingFilter() {
        draftFilter = filter
    }

    public func resetDraftFilter() {
        draftFilter = DiscoverFilter(
            certificationCountry: advancedDiscoverEnabled ? filter.region : nil,
            region: filter.region,
            includeAdult: filter.includeAdult
        )
    }

    public func applyDraftFilter(language: String) {
        filter = advancedDiscoverEnabled ? draftFilter : basicFilter(draftFilter)
        reload(language: language)
    }

    public func reload(language: String) {
        task?.cancel()
        configurationTask?.cancel()
        normalizeFilter()
        draftFilter = filter
        items = []
        page = 0
        canLoadMore = true
        errorMessage = nil
        configuration = nil
        let selectedType = mediaType
        let selectedFilter = filter
        let currentRequestID = UUID()
        requestID = currentRequestID
        let currentConfigurationRequestID = UUID()
        configurationRequestID = currentConfigurationRequestID
        isLoading = true
        let supportsAdvancedDiscover = advancedDiscoverEnabled
        if supportsAdvancedDiscover {
            configurationTask = Task { [weak self, catalog] in
                guard let self else { return }
                let loadedConfiguration = await Self.loadConfiguration(
                    catalog: catalog,
                    language: language,
                    region: selectedFilter.region
                )
                guard !Task.isCancelled,
                      configurationRequestID == currentConfigurationRequestID,
                      filter.region == selectedFilter.region,
                      advancedDiscoverEnabled else { return }
                configuration = loadedConfiguration
            }
        }
        task = Task { [weak self, catalog] in
            guard let self else { return }
            defer {
                if requestID == currentRequestID { isLoading = false }
            }
            do {
                async let genreRequest = catalog.genres(mediaType: selectedType, language: language)
                async let pageRequest = loadPage(
                    mediaType: selectedType,
                    filter: selectedFilter,
                    page: 1,
                    language: language,
                    supportsAdvancedDiscover: supportsAdvancedDiscover
                )
                let (loadedGenres, result) = try await (
                    genreRequest,
                    pageRequest
                )
                guard !Task.isCancelled,
                      requestID == currentRequestID,
                      mediaType == selectedType,
                      filter == selectedFilter,
                      advancedDiscoverEnabled == supportsAdvancedDiscover else { return }
                genres = loadedGenres
                items = result.results
                page = result.page
                canLoadMore = result.page < result.totalPages
            } catch is CancellationError {
                return
            } catch {
                if requestID == currentRequestID { errorMessage = error.localizedDescription }
            }
        }
    }

    private func normalizeFilter() {
        filter.releaseDateFrom = normalized(filter.releaseDateFrom)
        filter.releaseDateThrough = normalized(filter.releaseDateThrough)
        filter.originalLanguage = normalized(filter.originalLanguage)?.lowercased()
        filter.originCountry = normalized(filter.originCountry)?.uppercased()
        filter.certificationMinimum = normalized(filter.certificationMinimum)
        filter.certificationMaximum = normalized(filter.certificationMaximum)
        if let minimum = filter.minimumRuntime, let maximum = filter.maximumRuntime, minimum > maximum {
            filter.minimumRuntime = maximum
            filter.maximumRuntime = minimum
        }
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func loadConfiguration(
        catalog: any CatalogRepository,
        language: String,
        region: String?
    ) async -> DiscoverConfiguration? {
        guard let catalog = catalog as? any CatalogV2Repository else { return nil }
        return try? await catalog.discoverConfiguration(language: language, region: region)
    }

    private func loadPage(
        mediaType: MediaType,
        filter: DiscoverFilter,
        page: Int,
        language: String,
        supportsAdvancedDiscover: Bool
    ) async throws -> PagedResult<TitleSummary> {
        if supportsAdvancedDiscover {
            return try await catalog.discover(mediaType: mediaType, filter: filter, page: page, language: language)
        }
        return try await catalog.discoverBasic(mediaType: mediaType, filter: filter, page: page, language: language)
    }

    public func loadMoreIfNeeded(current item: TitleSummary, language: String) {
        guard item.id == items.last?.id, canLoadMore, !isLoading else { return }
        let nextPage = page + 1
        let selectedType = mediaType
        let selectedFilter = filter
        let supportsAdvancedDiscover = advancedDiscoverEnabled
        let currentRequestID = UUID()
        requestID = currentRequestID
        isLoading = true
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if requestID == currentRequestID { isLoading = false }
            }
            do {
                let result = try await loadPage(
                    mediaType: selectedType,
                    filter: selectedFilter,
                    page: nextPage,
                    language: language,
                    supportsAdvancedDiscover: supportsAdvancedDiscover
                )
                guard !Task.isCancelled,
                      requestID == currentRequestID,
                      mediaType == selectedType,
                      filter == selectedFilter,
                      advancedDiscoverEnabled == supportsAdvancedDiscover else { return }
                items.append(contentsOf: result.results.filter { incoming in
                    !items.contains(where: { $0.libraryKey == incoming.libraryKey })
                })
                page = result.page
                canLoadMore = result.page < result.totalPages
            } catch is CancellationError {
                return
            } catch {
                if requestID == currentRequestID { errorMessage = error.localizedDescription }
            }
        }
    }

    private func basicFilter(_ source: DiscoverFilter) -> DiscoverFilter {
        DiscoverFilter(
            genres: source.genres,
            year: source.year,
            minimumRating: source.minimumRating,
            sort: source.sort,
            region: source.region,
            includeAdult: source.includeAdult
        )
    }
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
        entities.compactMap { if case .title(let title) = $0 { title } else { nil } }
    }
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var canLoadMore = false
    public private(set) var hasSubmittedExternalID = false
    private let catalog: any CatalogRepository
    private var page = 0
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var includeAdult = false

    public init(catalog: any CatalogRepository) {
        self.catalog = catalog
    }

    public func setMode(_ mode: CatalogSearchMode) {
        guard self.mode != mode else { return }
        searchTask?.cancel()
        searchGeneration += 1
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
        searchGeneration += 1
        entities = []
        errorMessage = nil
        isLoading = false
        hasSubmittedExternalID = false
    }

    public func scheduleSearch(language: String, region: String? = nil, includeAdult: Bool = false) {
        searchTask?.cancel()
        searchGeneration += 1
        self.includeAdult = includeAdult
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
        let expectedGeneration = searchGeneration
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
                      searchGeneration == expectedGeneration,
                      self.includeAdult == includeAdult,
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

    public func findExternalID(language: String, includeAdult: Bool = false) {
        searchTask?.cancel()
        searchGeneration += 1
        self.includeAdult = includeAdult
        let externalID = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mode == .externalID, !externalID.isEmpty else {
            entities = []
            errorMessage = nil
            isLoading = false
            return
        }
        hasSubmittedExternalID = true
        let expectedSource = externalIDSource
        let expectedGeneration = searchGeneration
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
                      searchGeneration == expectedGeneration,
                      self.includeAdult == includeAdult,
                      mode == .externalID,
                      query.trimmingCharacters(in: .whitespacesAndNewlines) == externalID,
                      externalIDSource == expectedSource else { return }
                entities = result.results.filter { includeAdult || !$0.isAdultTitle }
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
        let expectedGeneration = searchGeneration
        isLoading = true
        searchTask = Task { [weak self, catalog] in
            guard let self else { return }
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
                guard !Task.isCancelled,
                      searchGeneration == expectedGeneration,
                      self.includeAdult == includeAdult,
                      query.trimmingCharacters(in: .whitespacesAndNewlines) == expectedQuery,
                      scope == expectedScope,
                      entityScope == expectedEntityScope else { return }
                entities.append(contentsOf: result.results.filter { incoming in
                    !entities.contains(where: { $0.id == incoming.id })
                })
                page = result.page
                canLoadMore = result.page < result.totalPages
                isLoading = false
            } catch is CancellationError {
                return
            } catch {
                guard searchGeneration == expectedGeneration else { return }
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    public func applyAdultVisibility(includeAdult: Bool) {
        self.includeAdult = includeAdult
        guard !includeAdult else { return }
        searchTask?.cancel()
        searchGeneration += 1
        entities.removeAll(where: \.isAdultTitle)
        isLoading = false
        canLoadMore = false
    }
}
