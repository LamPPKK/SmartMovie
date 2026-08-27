import XCTest
@testable import SmartMovieKit

@MainActor
final class FeatureModelTests: XCTestCase {
    func testHomeAvoidsDuplicateLoadAndForceRefreshes() async throws {
        let catalog = CatalogStub()
        let model = HomeViewModel(catalog: catalog)

        model.load(language: "en-US")
        try await waitUntil {
            if case .loaded = model.state { return true }
            return false
        }
        model.load(language: "en-US")
        try await Task.sleep(for: .milliseconds(30))
        let cachedCallCount = await catalog.homeCallCount()
        XCTAssertEqual(cachedCallCount, 1)

        model.load(language: "en-US", force: true)
        try await waitUntil {
            if case .loaded = model.state { return true }
            return false
        }
        let refreshedCallCount = await catalog.homeCallCount()
        XCTAssertEqual(refreshedCallCount, 2)
    }

    func testExploreReloadAndPaginationDeduplicateTitles() async throws {
        let first = sampleTitle(id: 1, title: "One")
        let duplicate = sampleTitle(id: 2, title: "Two")
        let third = sampleTitle(id: 3, title: "Three")
        let catalog = CatalogStub(discoverPages: [
            1: PagedResult(page: 1, totalPages: 2, results: [first, duplicate]),
            2: PagedResult(page: 2, totalPages: 2, results: [duplicate, third]),
        ])
        let model = ExploreViewModel(catalog: catalog)

        model.reload(language: "en-US")
        try await waitUntil { !model.isLoading && model.items.count == 2 }
        XCTAssertEqual(model.genres.map(\.id), [12, 18])
        XCTAssertTrue(model.canLoadMore)

        model.loadMoreIfNeeded(current: duplicate, language: "en-US")
        try await waitUntil { !model.isLoading && model.items.count == 3 }
        XCTAssertEqual(model.items.map(\.id), [1, 2, 3])
        XCTAssertFalse(model.canLoadMore)
        let pages = await catalog.discoveredPages()
        XCTAssertEqual(pages, [1, 2])
    }

    func testExploreContextChangeClearsProvidersAndResetPreservesSafetyContext() {
        let model = ExploreViewModel(catalog: CatalogStub())
        model.updateCapabilities(capabilities(advancedDiscover: true))

        XCTAssertTrue(model.updateContext(region: "us", includeAdult: true))
        model.filter.watchProviderIDs = [8, 337]
        model.filter.certificationMinimum = "PG-13"
        model.filter.certificationMaximum = "R"
        model.filter.minimumRating = 8
        XCTAssertTrue(model.updateContext(region: "vn", includeAdult: false))
        XCTAssertEqual(model.filter.region, "VN")
        XCTAssertEqual(model.filter.certificationCountry, "VN")
        XCTAssertFalse(model.filter.includeAdult)
        XCTAssertTrue(model.filter.watchProviderIDs.isEmpty)
        XCTAssertNil(model.filter.certificationMinimum)
        XCTAssertNil(model.filter.certificationMaximum)

        model.resetFilter()
        XCTAssertEqual(model.filter.region, "VN")
        XCTAssertEqual(model.filter.certificationCountry, "VN")
        XCTAssertFalse(model.filter.includeAdult)
        XCTAssertEqual(model.filter.minimumRating, 0)
        XCTAssertFalse(model.updateContext(region: "VN", includeAdult: false))
    }

    func testExploreDraftDoesNotChangeAppliedFilterUntilApply() {
        let model = ExploreViewModel(catalog: CatalogStub())
        _ = model.updateContext(region: "US", includeAdult: false)
        model.beginEditingFilter()
        model.draftFilter.minimumRating = 8
        model.draftFilter.watchProviderIDs = [8]

        XCTAssertEqual(model.filter.minimumRating, 0)
        XCTAssertTrue(model.filter.watchProviderIDs.isEmpty)

        model.beginEditingFilter()
        XCTAssertEqual(model.draftFilter, model.filter)
    }

    func testExploreRejectsStalePaginationAfterContextReload() async throws {
        let catalog = StaleExploreCatalog()
        let model = ExploreViewModel(catalog: catalog)
        _ = model.updateContext(region: "US", includeAdult: true)
        model.reload(language: "en-US")
        try await waitUntil { !model.isLoading && model.items.map(\.id) == [1] }

        model.loadMoreIfNeeded(current: try XCTUnwrap(model.items.last), language: "en-US")
        _ = model.updateContext(region: "VN", includeAdult: false)
        model.reload(language: "vi-VN")
        try await waitUntil { !model.isLoading && model.items.map(\.id) == [10] }
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(model.items.map(\.id), [10])
        XCTAssertFalse(model.filter.includeAdult)
        XCTAssertEqual(model.filter.region, "VN")
    }

    func testExploreReloadUsesNewLanguageWhenOnlyLocaleChanges() async throws {
        let catalog = CatalogStub()
        let model = ExploreViewModel(catalog: catalog)
        _ = model.updateContext(region: "US", includeAdult: false)

        model.reload(language: "en-US")
        try await waitUntil { !model.isLoading }
        model.reload(language: "vi-VN")
        try await waitUntil { !model.isLoading }

        let languages = await catalog.discoveredLanguages()
        XCTAssertEqual(languages, ["en-US", "vi-VN"])
    }

    func testExploreCapabilitiesGateAdvancedStateAndRequestRoute() async throws {
        let catalog = CatalogStub()
        let model = ExploreViewModel(catalog: catalog)

        XCTAssertFalse(model.updateCapabilities(nil))
        XCTAssertFalse(model.advancedDiscoverEnabled)
        XCTAssertFalse(model.updateCapabilities(capabilities(advancedDiscover: false)))
        XCTAssertFalse(model.advancedDiscoverEnabled)
        XCTAssertTrue(model.updateCapabilities(capabilities(advancedDiscover: true)))
        XCTAssertTrue(model.advancedDiscoverEnabled)

        model.reload(language: "en-US")
        try await waitUntil { !model.isLoading }
        let advancedModes = await catalog.discoverModes()
        XCTAssertEqual(advancedModes, ["advanced"])

        model.filter.releaseDateFrom = "2026-01-01"
        model.filter.watchProviderIDs = [8]
        XCTAssertTrue(model.updateCapabilities(capabilities(advancedDiscover: false)))
        XCTAssertNil(model.filter.releaseDateFrom)
        XCTAssertTrue(model.filter.watchProviderIDs.isEmpty)
        model.reload(language: "en-US")
        try await waitUntil { !model.isLoading }
        let fallbackModes = await catalog.discoverModes()
        XCTAssertEqual(fallbackModes, ["advanced", "basic"])
    }

    func testSearchCancelsOldRequestAndRejectsStaleResults() async throws {
        let catalog = CatalogStub()
        let model = SearchViewModel(catalog: catalog)

        model.query = "old"
        model.scheduleSearch(language: "en-US")
        try await Task.sleep(for: .milliseconds(400))
        model.query = "new"
        model.scheduleSearch(language: "en-US")
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(model.items.map(\.title), ["new"])
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
    }

    func testSearchClearsResultsForBlankQueryAndSurfacesError() async throws {
        let catalog = CatalogStub(searchFailure: true)
        let model = SearchViewModel(catalog: catalog)

        model.query = "failure"
        model.scheduleSearch(language: "en-US")
        try await waitUntil { model.errorMessage != nil }
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertFalse(model.isLoading)

        model.query = "   "
        model.scheduleSearch(language: "en-US")
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertFalse(model.canLoadMore)
    }

    func testSearchFindsEntitiesByExternalIDWithoutDebouncing() async throws {
        let catalog = ExternalIDCatalogStub()
        let model = SearchViewModel(catalog: catalog)
        model.setMode(.externalID)
        model.externalIDSource = .wikidata
        model.query = " Q83495 "

        model.findExternalID(language: "vi-VN")
        try await waitUntil { !model.isLoading && !model.entities.isEmpty }

        XCTAssertEqual(model.entities.map(\.kind), [.movie, .person])
        let requests = await catalog.externalIDRequests()
        XCTAssertEqual(requests, ["Q83495|wikidata_id|vi-VN|false"])
        XCTAssertFalse(model.canLoadMore)
    }

    func testTrailerPrefersOfficialYouTubeTrailerInRequestedLanguage() async {
        let catalog = CatalogStub()
        let library = LibraryStub()
        let summary = TitleSummary(id: 1, mediaType: .movie, title: "Film", originalTitle: "Film", overview: "")
        let model = DetailViewModel(summary: summary, catalog: catalog, library: library)

        await model.load(language: "vi-VN")

        XCTAssertEqual(model.preferredTrailer(language: "vi-VN")?.key, "vi-official")
    }

    func testTrailerFallsBackToAnyYouTubeTrailerBeforeTeaser() async {
        let videos = [
            Video(id: "1", key: "teaser", name: "Teaser", site: "YouTube", type: "Teaser", official: true, language: "vi"),
            Video(id: "2", key: "wrong-site", name: "Trailer", site: "Vimeo", type: "Trailer", official: true, language: "vi"),
            Video(id: "3", key: "generic-trailer", name: "Trailer", site: "YouTube", type: "Trailer", official: false, language: "en"),
        ]
        let catalog = CatalogStub(detailVideos: videos)
        let summary = sampleTitle(id: 1, title: "Film")
        let model = DetailViewModel(summary: summary, catalog: catalog, library: LibraryStub())

        await model.load(language: "vi-VN")

        XCTAssertEqual(model.preferredTrailer(language: "vi-VN")?.key, "generic-trailer")
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for asynchronous state")
    }

    private func capabilities(advancedDiscover: Bool) -> CapabilitiesV2 {
        CapabilitiesV2(
            apiVersion: "v2",
            releaseTrain: "3.0.0",
            catalog: ["advanced_discover": advancedDiscover]
        )
    }
}

private actor CatalogStub: CatalogRepository {
    private let discoverPages: [Int: PagedResult<TitleSummary>]
    private let searchFailure: Bool
    private let detailVideos: [Video]
    private var homeCalls = 0
    private var requestedDiscoverPages: [Int] = []
    private var requestedDiscoverLanguages: [String] = []
    private var requestedDiscoverModes: [String] = []

    init(
        discoverPages: [Int: PagedResult<TitleSummary>] = [:],
        searchFailure: Bool = false,
        detailVideos: [Video]? = nil
    ) {
        self.discoverPages = discoverPages
        self.searchFailure = searchFailure
        self.detailVideos = detailVideos ?? [
            Video(id: "1", key: "generic", name: "Trailer", site: "YouTube", type: "Trailer", official: true, language: "en"),
            Video(id: "2", key: "vi-official", name: "Trailer", site: "YouTube", type: "Trailer", official: true, language: "vi"),
            Video(id: "3", key: "teaser", name: "Teaser", site: "YouTube", type: "Teaser", official: true, language: "vi"),
        ]
    }

    func home(mediaType: MediaType, language: String) async throws -> HomeFeed {
        homeCalls += 1
        return HomeFeed(mediaType: mediaType, hero: nil, sections: [])
    }

    func homeCallCount() -> Int { homeCalls }

    func genres(mediaType: MediaType, language: String) async throws -> [Genre] {
        [Genre(id: 12, name: "Adventure"), Genre(id: 18, name: "Drama")]
    }

    func discover(mediaType: MediaType, filter: DiscoverFilter, page: Int, language: String) async throws -> PagedResult<TitleSummary> {
        requestedDiscoverPages.append(page)
        requestedDiscoverLanguages.append(language)
        requestedDiscoverModes.append("advanced")
        return discoverPages[page] ?? PagedResult(page: page, totalPages: page, results: [])
    }

    func discoverBasic(
        mediaType: MediaType,
        filter: DiscoverFilter,
        page: Int,
        language: String
    ) async throws -> PagedResult<TitleSummary> {
        requestedDiscoverPages.append(page)
        requestedDiscoverLanguages.append(language)
        requestedDiscoverModes.append("basic")
        return discoverPages[page] ?? PagedResult(page: page, totalPages: page, results: [])
    }

    func discoveredPages() -> [Int] { requestedDiscoverPages }
    func discoveredLanguages() -> [String] { requestedDiscoverLanguages }
    func discoverModes() -> [String] { requestedDiscoverModes }

    func search(query: String, scope: SearchScope, page: Int, language: String) async throws -> PagedResult<TitleSummary> {
        if searchFailure { throw APIError.server(status: 503, requestID: "feature-test") }
        if query == "old" {
            try await Task.sleep(for: .milliseconds(500))
        } else {
            try await Task.sleep(for: .milliseconds(20))
        }
        let result = TitleSummary(id: query == "old" ? 1 : 2, mediaType: .movie, title: query, originalTitle: query, overview: "")
        return PagedResult(page: 1, totalPages: 1, results: [result])
    }

    func detail(mediaType: MediaType, id: Int, language: String) async throws -> TitleDetail {
        TitleDetail(
            id: id,
            mediaType: mediaType,
            title: "Film",
            originalTitle: "Film",
            overview: "",
            videos: detailVideos
        )
    }

    func imageConfiguration() async throws -> ImageConfiguration {
        ImageConfiguration(secureBaseURL: "https://image.tmdb.org/t/p/", posterSizes: ["w500"], backdropSizes: ["w1280"], profileSizes: ["w185"])
    }

}

private actor StaleExploreCatalog: CatalogRepository {
    func home(mediaType: MediaType, language: String) async throws -> HomeFeed {
        HomeFeed(mediaType: mediaType, hero: nil, sections: [])
    }

    func genres(mediaType: MediaType, language: String) async throws -> [Genre] { [] }

    func discover(
        mediaType: MediaType,
        filter: DiscoverFilter,
        page: Int,
        language: String
    ) async throws -> PagedResult<TitleSummary> {
        if page == 2 {
            try? await Task.sleep(for: .milliseconds(200))
            return PagedResult(page: 2, totalPages: 2, results: [sampleTitle(id: 2, title: "Stale adult")])
        }
        let title = filter.region == "VN"
            ? sampleTitle(id: 10, title: "Vietnam")
            : sampleTitle(id: 1, title: "United States")
        return PagedResult(page: 1, totalPages: 2, results: [title])
    }

    func search(
        query: String,
        scope: SearchScope,
        page: Int,
        language: String
    ) async throws -> PagedResult<TitleSummary> {
        PagedResult(page: page, totalPages: page, results: [])
    }

    func detail(mediaType: MediaType, id: Int, language: String) async throws -> TitleDetail {
        TitleDetail(id: id, mediaType: mediaType, title: "", originalTitle: "", overview: "")
    }

    func imageConfiguration() async throws -> ImageConfiguration {
        ImageConfiguration(
            secureBaseURL: "https://image.tmdb.org/t/p/",
            posterSizes: [],
            backdropSizes: [],
            profileSizes: []
        )
    }
}

private actor ExternalIDCatalogStub: CatalogRepository, CatalogV2Repository {
    private var requests: [String] = []

    func home(mediaType: MediaType, language: String) async throws -> HomeFeed { throw APIError.notFound }
    func genres(mediaType: MediaType, language: String) async throws -> [Genre] { throw APIError.notFound }
    func discover(
        mediaType: MediaType,
        filter: DiscoverFilter,
        page: Int,
        language: String
    ) async throws -> PagedResult<TitleSummary> { throw APIError.notFound }
    func search(
        query: String,
        scope: SearchScope,
        page: Int,
        language: String
    ) async throws -> PagedResult<TitleSummary> { throw APIError.notFound }
    func detail(mediaType: MediaType, id: Int, language: String) async throws -> TitleDetail { throw APIError.notFound }
    func imageConfiguration() async throws -> ImageConfiguration { throw APIError.notFound }
    func capabilities() async throws -> CapabilitiesV2 { throw APIError.notFound }
    func discoverConfiguration(language: String, region: String?) async throws -> DiscoverConfiguration {
        throw APIError.notFound
    }
    func trending(
        kind: String,
        window: String,
        page: Int,
        language: String,
        includeAdult: Bool
    ) async throws -> PagedResult<CatalogEntity> { throw APIError.notFound }
    func searchEntities(_ request: EntitySearchRequest) async throws -> PagedResult<CatalogEntity> { throw APIError.notFound }

    func findExternalID(
        _ externalID: String,
        source: ExternalIDSource,
        language: String,
        includeAdult: Bool
    ) async throws -> ExternalIDFindResult {
        requests.append("\(externalID)|\(source.rawValue)|\(language)|\(includeAdult)")
        return ExternalIDFindResult(
            source: source,
            externalID: externalID,
            results: [
                .title(sampleTitle(id: 603, title: "The Matrix")),
                .person(PersonSummary(
                    id: 6384,
                    name: "Keanu Reeves",
                    profilePath: nil,
                    knownForDepartment: "Acting",
                    popularity: 1,
                    knownFor: []
                ))
            ]
        )
    }

    func externalIDRequests() -> [String] { requests }
    func deepDetail(
        mediaType: MediaType,
        id: Int,
        language: String,
        region: String?,
        includeAdult: Bool
    ) async throws -> TitleDetailV2 { throw APIError.notFound }
    func person(id: Int, language: String, includeAdult: Bool) async throws -> PersonDetail { throw APIError.notFound }
    func collection(id: Int, language: String, includeAdult: Bool) async throws -> CollectionDetail { throw APIError.notFound }
    func organization(
        kind: EntityKind,
        id: Int,
        language: String,
        page: Int,
        includeAdult: Bool
    ) async throws -> OrganizationDetail {
        throw APIError.notFound
    }
    func keyword(id: Int, language: String, page: Int, includeAdult: Bool) async throws -> KeywordDetail {
        throw APIError.notFound
    }
    func season(seriesID: Int, number: Int, language: String) async throws -> SeasonDetail { throw APIError.notFound }
    func episode(seriesID: Int, season: Int, number: Int, language: String) async throws -> EpisodeDetail { throw APIError.notFound }
    func credit(id: String, language: String, includeAdult: Bool) async throws -> CreditDetail { throw APIError.notFound }
}

private func sampleTitle(id: Int, title: String, mediaType: MediaType = .movie) -> TitleSummary {
    TitleSummary(id: id, mediaType: mediaType, title: title, originalTitle: title, overview: "Overview")
}

@MainActor
private final class LibraryStub: LibraryRepository {
    func contains(_ title: TitleSummary, in collection: LibraryCollection) throws -> Bool { false }
    func toggle(_ title: TitleSummary, in collection: LibraryCollection) throws {}
    func items(in collection: LibraryCollection, mediaType: MediaType?, sort: LibrarySort) throws -> [LibrarySnapshot] { [] }
    func reconcileDuplicates() throws {}
}
