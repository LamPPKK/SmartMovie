import XCTest
@testable import SmartMovieKit

@MainActor
final class AdultSearchPrivacyTests: XCTestCase {
    func testEntityRelatedTitlesAndCreditsFailClosed() throws {
        let safe = TitleSummary(
            id: 1,
            mediaType: .movie,
            title: "Safe",
            originalTitle: "Safe",
            overview: ""
        )
        let restricted = TitleSummary(
            id: 2,
            mediaType: .movie,
            title: "Restricted",
            originalTitle: "Restricted",
            overview: "",
            isAdult: true
        )
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let credits = try decoder.decode([Credit].self, from: Data(#"""
        [
          {"credit_id":"safe","id":1,"media_type":"movie","title":"Safe","adult":false},
          {"credit_id":"restricted","id":2,"media_type":"movie","title":"Restricted","adult":true},
          {"credit_id":"legacy","id":3,"media_type":"movie","title":"Legacy"}
        ]
        """#.utf8))

        XCTAssertEqual(
            CatalogAdultVisibility.titles([safe, restricted], includeAdult: false).map(\.libraryKey),
            ["movie:1"]
        )
        XCTAssertEqual(
            CatalogAdultVisibility.credits(credits, includeAdult: false).compactMap(\.creditId),
            ["safe", "legacy"]
        )
        XCTAssertEqual(CatalogAdultVisibility.credits(credits, includeAdult: true).count, 3)

        let people = [CatalogEntity.person(PersonSummary(
            id: 7,
            name: "Person",
            profilePath: nil,
            knownForDepartment: "Acting",
            popularity: 1,
            knownFor: [safe, restricted]
        ))]
        let visiblePerson = try XCTUnwrap(people.applyingAdultVisibility(includeAdult: false).first)
        guard case .person(let person) = visiblePerson else { return XCTFail("Expected a person entity") }
        XCTAssertEqual(person.knownFor.map(\.libraryKey), ["movie:1"])

        let season = CatalogEntity.season(SeasonSummary(
            id: 13,
            seasonNumber: 1,
            name: "Season",
            overview: "",
            posterPath: nil,
            airDate: nil,
            voteAverage: nil,
            episodeCount: 8
        ))
        let episode = CatalogEntity.episode(EpisodeSummary(
            id: 14,
            seriesId: 15,
            seasonNumber: 1,
            episodeNumber: 1,
            name: "Episode",
            overview: "",
            stillPath: nil,
            airDate: nil,
            runtimeMinutes: nil,
            voteAverage: nil
        ))
        XCTAssertTrue([season, episode].applyingAdultVisibility(includeAdult: false).isEmpty)
        XCTAssertEqual([season, episode].applyingAdultVisibility(includeAdult: true).count, 2)

        let creditDetail = CreditDetail(
            creditId: "restricted",
            creditType: "cast",
            department: "Acting",
            job: nil,
            character: "Role",
            personSummary: nil,
            titleSummary: restricted
        )
        XCTAssertNil(creditDetail.applyingAdultVisibility(includeAdult: false).titleSummary)
        XCTAssertEqual(creditDetail.applyingAdultVisibility(includeAdult: true).titleSummary?.libraryKey, "movie:2")
    }

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
