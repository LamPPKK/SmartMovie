import XCTest
@testable import SmartMovieKit

@MainActor
final class AdultSearchPrivacyTests: XCTestCase {
    func testLockPurgesAdultResultsAndInvalidatesInFlightRequest() async throws {
        let adult = TitleSummary(
            id: 99,
            mediaType: .movie,
            title: "Restricted",
            originalTitle: "Restricted",
            overview: "",
            isAdult: true
        )
        let model = SearchViewModel(catalog: AdultSearchCatalogStub(result: adult))

        model.query = "restricted"
        model.scheduleSearch(language: "en-US", includeAdult: true)
        try await Task.sleep(for: .milliseconds(400))
        model.applyAdultVisibility(includeAdult: false)
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertTrue(model.entities.isEmpty)
        XCTAssertFalse(model.isLoading)
    }
}

private actor AdultSearchCatalogStub: CatalogRepository {
    let result: TitleSummary

    init(result: TitleSummary) { self.result = result }

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
        PagedResult(page: page, totalPages: page, results: [])
    }

    func search(query: String, scope: SearchScope, page: Int, language: String) async throws -> PagedResult<TitleSummary> {
        try await Task.sleep(for: .milliseconds(100))
        return PagedResult(page: page, totalPages: page, results: [result])
    }

    func detail(mediaType: MediaType, id: Int, language: String) async throws -> TitleDetail {
        throw APIError.notFound
    }

    func imageConfiguration() async throws -> ImageConfiguration {
        ImageConfiguration(
            secureBaseURL: "https://image.tmdb.org/t/p/",
            posterSizes: ["w500"],
            backdropSizes: ["w1280"],
            profileSizes: ["w185"]
        )
    }
}
