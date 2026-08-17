import Foundation
import XCTest
@testable import SmartMovieKit

final class ContractConformanceTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    func testCanonicalSuccessFixturesDecodeIntoNativeModels() throws {
        let home = try decode(HomeFeed.self, fixture: "home")
        XCTAssertEqual(home.mediaType, .movie)
        XCTAssertEqual(home.hero?.libraryKey, "movie:42")

        let page = try decode(PagedResult<TitleSummary>.self, fixture: "title-page")
        XCTAssertEqual(page.results.first?.libraryKey, "movie:42")

        let genres = try decode(GenreEnvelope.self, fixture: "genres")
        XCTAssertEqual(genres.genres.map(\.id), [12, 18])

        let detail = try decode(TitleDetail.self, fixture: "title-detail")
        XCTAssertEqual(detail.cast.first?.character, "Lead")
        XCTAssertEqual(detail.videos.first?.official, true)

        let configuration = try decode(ImageConfiguration.self, fixture: "configuration")
        XCTAssertEqual(configuration.posterSizes, ["w342", "w500", "original"])
    }

    func testCanonicalErrorFixtureDecodes() throws {
        let envelope = try decode(ErrorEnvelope.self, fixture: "error")

        XCTAssertEqual(envelope.error.code, "rate_limited")
        XCTAssertEqual(envelope.error.retryAfter, 60)
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(envelope.error.requestId)))
    }

    func testAdditiveFieldsAndMissingNullableFieldsRemainCompatible() throws {
        let summary = try decode(TitleSummary.self, fixture: "title-summary-forward-compatible")

        XCTAssertEqual(summary.libraryKey, "tv:99")
        XCTAssertNil(summary.posterPath)
        XCTAssertNil(summary.backdropPath)
        XCTAssertNil(summary.releaseDate)
    }

    private func decode<Value: Decodable>(_ type: Value.Type, fixture: String) throws -> Value {
        try decoder.decode(type, from: Data(contentsOf: fixtureURL(fixture)))
    }

    private func fixtureURL(_ name: String) -> URL {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repositoryRoot
            .appending(path: "backend/worker/contract/fixtures")
            .appending(path: "\(name).json")
    }
}

private struct GenreEnvelope: Decodable {
    let genres: [Genre]
}
