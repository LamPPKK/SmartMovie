import Foundation
import XCTest
@testable import SmartMovieKit

final class ContractV2ConformanceTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func testAllCanonicalV2EntitiesDecode() throws {
        let capabilities = try decode(CapabilitiesV2.self, fixture: "capabilities")
        XCTAssertEqual(capabilities.apiVersion, "v2")
        XCTAssertEqual(Set(capabilities.supportedEntityKinds), Set(EntityKind.allCases))

        let page = try decode(PagedResult<CatalogEntity>.self, fixture: "entities")
        XCTAssertEqual(Set(page.results.map(\.kind)), Set(EntityKind.allCases))

        let find = try decode(ExternalIDFindResult.self, fixture: "find")
        XCTAssertEqual(find.source, .imdb)
        XCTAssertEqual(find.externalID, "tt0000010")
        XCTAssertEqual(find.results.map(\.kind), [.movie, .person])

        let detail = try decode(TitleDetailV2.self, fixture: "title-detail")
        XCTAssertEqual(detail.summary.libraryKey, "movie:10")
        XCTAssertEqual(detail.watchProviders.first?.attribution, "JustWatch")
        XCTAssertEqual(detail.externalIDs["imdb_id"], "tt0000010")

        XCTAssertEqual(try decode(PersonDetail.self, fixture: "person").id, 12)
        XCTAssertEqual(try decode(CollectionDetail.self, fixture: "collection").id, 13)
        XCTAssertEqual(try decode(SeasonDetail.self, fixture: "season").episodes.first?.episodeKey, "11:1:1")
        XCTAssertEqual(try decode(EpisodeDetail.self, fixture: "episode").episodeNumber, 1)
    }

    func testAccountAuthMutationAndErrorFixturesDecode() throws {
        let account = try decode(AccountFixture.self, fixture: "account")
        XCTAssertTrue(account.state.favorite)
        XCTAssertEqual(account.list.results.map(\.libraryKey), ["movie:10", "tv:11"])

        let attempt = try decode(AuthAttempt.self, fixture: "auth-attempt")
        XCTAssertEqual(attempt.status, "pending")
        XCTAssertEqual(attempt.authorizationUrl.host, "www.themoviedb.org")

        let mutation = try decode(MutationResult.self, fixture: "mutation")
        XCTAssertEqual(mutation.success, true)

        let error = try decode(ErrorEnvelope.self, fixture: "error")
        XCTAssertNotNil(error.error.requestId)
    }

    func testUnknownFieldsAndMissingNullableFieldsAreForwardCompatible() throws {
        let detail = try decode(TitleDetailV2.self, fixture: "title-detail")
        XCTAssertNil(detail.posterPath)

        let data = Data(#"""
        {
          "entity_kind": "person",
          "id": 99,
          "name": "Future Person",
          "profile_path": null,
          "known_for_department": null,
          "popularity": 0,
          "known_for": [],
          "future": {"nested": true}
        }
        """#.utf8)
        let entity = try decoder.decode(CatalogEntity.self, from: data)
        XCTAssertEqual(entity.kind, .person)
        XCTAssertEqual(entity.displayName, "Future Person")
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
            .appending(path: "backend/worker/contract/v2/fixtures")
            .appending(path: "\(name).json")
    }
}

private struct AccountFixture: Decodable {
    let profile: AccountProfile
    let state: AccountState
    let list: UserList
}
