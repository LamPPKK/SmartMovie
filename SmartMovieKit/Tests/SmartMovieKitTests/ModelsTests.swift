import XCTest
@testable import SmartMovieKit

final class ModelsTests: XCTestCase {
    func testDetailFixtureDecodesStableContract() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "title-detail", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let detail = try decoder.decode(TitleDetail.self, from: data)

        XCTAssertEqual(detail.id, 42)
        XCTAssertEqual(detail.mediaType, .movie)
        XCTAssertEqual(detail.cast.first?.character, "Lead")
        XCTAssertEqual(detail.videos.first?.official, true)
        XCTAssertEqual(detail.summary.libraryKey, "movie:42")
    }

    func testLocaleResolverSupportsEveryShippedLanguage() {
        XCTAssertEqual(LocaleResolver.tmdbLanguage(for: Locale(identifier: "vi_VN")), "vi-VN")
        XCTAssertEqual(LocaleResolver.tmdbLanguage(for: Locale(identifier: "ja_JP")), "ja-JP")
        XCTAssertEqual(LocaleResolver.tmdbLanguage(for: Locale(identifier: "ko_KR")), "ko-KR")
        XCTAssertEqual(LocaleResolver.tmdbLanguage(for: Locale(identifier: "zh_Hans_CN")), "zh-CN")
        XCTAssertEqual(LocaleResolver.tmdbLanguage(for: Locale(identifier: "zh_Hant_TW")), "zh-TW")
        XCTAssertEqual(LocaleResolver.tmdbLanguage(for: Locale(identifier: "fr_FR")), "en-US")
    }

    func testAccountAuthenticationCapabilityFailsClosedAndUsesCanonicalKeys() {
        let disabled = CapabilitiesV2(apiVersion: "v2", releaseTrain: "3.0.0", catalog: [:])
        let browser = CapabilitiesV2(
            apiVersion: "v2",
            releaseTrain: "3.0.0",
            catalog: [:],
            account: ["browser_auth": true]
        )
        let television = CapabilitiesV2(
            apiVersion: "v2",
            releaseTrain: "3.0.0",
            catalog: [:],
            account: ["tv_qr_auth": true]
        )

        XCTAssertFalse(supportsAccountAuthentication(nil, mode: "browser"))
        XCTAssertFalse(supportsAccountAuthentication(disabled, mode: "browser"))
        XCTAssertTrue(supportsAccountAuthentication(browser, mode: "browser"))
        XCTAssertFalse(supportsAccountAuthentication(browser, mode: "tv"))
        XCTAssertTrue(supportsAccountAuthentication(television, mode: "tv"))
        XCTAssertFalse(supportsAccountAuthentication(television, mode: "unknown"))
    }

    func testAuthCallbackGateDefersUntilCapabilityResolutionAndFailsClosed() throws {
        let callback = try XCTUnwrap(URL(string: "smartmovie://auth/callback?auth_attempt=00000000-0000-0000-0000-000000000001"))
        var unavailable = AccountCapabilityGate()
        XCTAssertNil(unavailable.submit(callback))
        XCTAssertNil(unavailable.resolve(enabled: false))
        XCTAssertNil(unavailable.submit(callback))

        var enabled = AccountCapabilityGate()
        XCTAssertNil(enabled.submit(callback))
        XCTAssertEqual(enabled.resolve(enabled: true), callback)
        XCTAssertEqual(enabled.submit(callback), callback)
    }

    func testTVSummaryUsesSharedFallbackFields() throws {
        let json = #"""
        {
          "id": 77,
          "media_type": "tv",
          "title": "",
          "original_title": "原題",
          "overview": "",
          "release_date": "2025-04-03",
          "vote_average": 8.2,
          "genre_ids": [18]
        }
        """#
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let summary = try decoder.decode(TitleSummary.self, from: data)

        XCTAssertEqual(summary.mediaType, .tv)
        XCTAssertEqual(summary.displayTitle, "原題")
        XCTAssertEqual(summary.releaseYear, "2025")
        XCTAssertEqual(summary.libraryKey, "tv:77")
        XCTAssertEqual(summary.genreIDs, [18])
    }

    func testImageConfigurationDecodesWorkerSnakeCaseContract() throws {
        let data = Data(#"{"secure_base_url":"https://cdn.example/","poster_sizes":["w500"],"backdrop_sizes":["w1280"],"profile_sizes":["w185"]}"#.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let configuration = try decoder.decode(ImageConfiguration.self, from: data)

        XCTAssertEqual(configuration.secureBaseURL, "https://cdn.example/")
        XCTAssertEqual(configuration.posterSizes, ["w500"])
    }

    @MainActor
    func testImageURLUsesConfigurationSizesAndNormalizesPaths() {
        let container = AppContainer(catalog: NoopCatalog(), library: NoopLibrary())

        XCTAssertEqual(
            container.imageURL(path: "/poster.jpg", kind: .poster)?.absoluteString,
            "https://image.tmdb.org/t/p/w500/poster.jpg"
        )
        XCTAssertEqual(
            container.imageURL(path: "face.jpg", kind: .profile)?.absoluteString,
            "https://image.tmdb.org/t/p/w185/face.jpg"
        )
        XCTAssertNil(container.imageURL(path: nil, kind: .backdrop))
        XCTAssertNil(container.imageURL(path: "", kind: .backdrop))
    }
}

private actor NoopCatalog: CatalogRepository {
    func home(mediaType: MediaType, language: String) async throws -> HomeFeed {
        HomeFeed(mediaType: mediaType, hero: nil, sections: [])
    }
    func genres(mediaType: MediaType, language: String) async throws -> [Genre] { [] }
    func discover(mediaType: MediaType, filter: DiscoverFilter, page: Int, language: String) async throws -> PagedResult<TitleSummary> {
        PagedResult(page: page, totalPages: page, results: [])
    }
    func search(query: String, scope: SearchScope, page: Int, language: String) async throws -> PagedResult<TitleSummary> {
        PagedResult(page: page, totalPages: page, results: [])
    }
    func detail(mediaType: MediaType, id: Int, language: String) async throws -> TitleDetail {
        TitleDetail(id: id, mediaType: mediaType, title: "", originalTitle: "", overview: "")
    }
    func imageConfiguration() async throws -> ImageConfiguration {
        ImageConfiguration(secureBaseURL: "https://image.tmdb.org/t/p/", posterSizes: ["w500"], backdropSizes: ["w1280"], profileSizes: ["w185"])
    }
}

@MainActor
private final class NoopLibrary: LibraryRepository {
    func contains(_ title: TitleSummary, in collection: LibraryCollection) throws -> Bool { false }
    func toggle(_ title: TitleSummary, in collection: LibraryCollection) throws {}
    func items(in collection: LibraryCollection, mediaType: MediaType?, sort: LibrarySort) throws -> [LibrarySnapshot] { [] }
    func reconcileDuplicates() throws {}
}
