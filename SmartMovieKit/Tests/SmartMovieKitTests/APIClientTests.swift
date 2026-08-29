import Foundation
import XCTest
@testable import SmartMovieKit

final class APIClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocolStub.reset()
    }

    func testGetBuildsRequestHeadersQueryAndDecodesSnakeCase() async throws {
        URLProtocolStub.enqueue(status: 200, body: #"{"display_name":"SmartMovie"}"#)
        let client = makeClient()

        let response: TestPayload = try await client.get("/v1/test", queryItems: [
            URLQueryItem(name: "language", value: "vi-VN"),
            URLQueryItem(name: "query", value: "star wars"),
        ])

        XCTAssertEqual(response.displayName, "SmartMovie")
        let request = try XCTUnwrap(URLProtocolStub.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-SmartMovie-Client"), "unit-test-client")
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/api/v1/test")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "language" })?.value, "vi-VN")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "query" })?.value, "star wars")
    }

    func testRetriesServerErrorsThenReturnsSuccessfulResponse() async throws {
        URLProtocolStub.enqueue(status: 503, body: errorBody(code: "upstream_error", requestID: "one"))
        URLProtocolStub.enqueue(status: 502, body: errorBody(code: "upstream_error", requestID: "two"))
        URLProtocolStub.enqueue(status: 200, body: #"{"display_name":"Recovered"}"#)

        let response: TestPayload = try await makeClient().get("v1/test")

        XCTAssertEqual(response.displayName, "Recovered")
        XCTAssertEqual(URLProtocolStub.requests.count, 3)
    }

    func testMapsRateLimitPayloadAfterBoundedRetries() async throws {
        for _ in 0 ..< 3 {
            URLProtocolStub.enqueue(
                status: 429,
                headers: ["Retry-After": "9"],
                body: #"{"error":{"code":"rate_limited","message":"Busy","request_id":"rate-id","retry_after":0}}"#
            )
        }

        do {
            let _: TestPayload = try await makeClient().get("v1/test")
            XCTFail("Expected rate limit error")
        } catch {
            XCTAssertEqual(error as? APIError, .rateLimited(retryAfter: 0))
            XCTAssertEqual(URLProtocolStub.requests.count, 3)
        }
    }

    func testDoesNotRetryUnauthorizedNotFoundOrDecodingErrors() async throws {
        URLProtocolStub.enqueue(status: 401, body: errorBody(code: "unauthorized", requestID: "auth"))
        await assertError(.unauthorized)
        XCTAssertEqual(URLProtocolStub.requests.count, 1)

        URLProtocolStub.reset()
        URLProtocolStub.enqueue(status: 404, body: errorBody(code: "not_found", requestID: "missing"))
        await assertError(.notFound)
        XCTAssertEqual(URLProtocolStub.requests.count, 1)

        URLProtocolStub.reset()
        URLProtocolStub.enqueue(status: 200, body: "not-json")
        do {
            let _: TestPayload = try await makeClient().get("v1/test")
            XCTFail("Expected decoding error")
        } catch {
            guard case .decoding = error as? APIError else {
                return XCTFail("Expected decoding error, got \(error)")
            }
        }
        XCTAssertEqual(URLProtocolStub.requests.count, 1)
    }

    func testRemoteRepositoryEncodesDiscoverFiltersDeterministically() async throws {
        URLProtocolStub.enqueue(status: 200, body: #"{"page":3,"total_pages":3,"results":[]}"#)
        let repository = RemoteCatalogRepository(client: makeClient())
        let filter = DiscoverFilter(
            genres: [28, 12],
            year: 2026,
            minimumRating: 7.5,
            sort: .releaseDate,
            releaseDateFrom: "2024-01-01",
            releaseDateThrough: "2026-08-26",
            originalLanguage: "ko",
            originCountry: "KR",
            certificationCountry: "US",
            certificationMinimum: "PG",
            certificationMaximum: "R",
            minimumRuntime: 60,
            maximumRuntime: 180,
            minimumVoteCount: 100,
            region: "VN",
            watchProviderIDs: [337, 8],
            monetizationTypes: [.subscription, .buy],
            includeAdult: true
        )

        let response = try await repository.discover(
            mediaType: .movie,
            filter: filter,
            page: 3,
            language: "ko-KR"
        )

        XCTAssertEqual(response.page, 3)
        let request = try XCTUnwrap(URLProtocolStub.requests.first)
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = try XCTUnwrap(components.queryItems)
        let query = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value) })
        XCTAssertEqual(url.path, "/api/v2/discover/movie")
        XCTAssertEqual(query["genres"], "12,28")
        XCTAssertEqual(query["year"], "2026")
        XCTAssertEqual(query["vote_average_gte"], "7.5")
        XCTAssertEqual(query["sort_by"], "primary_release_date.desc")
        XCTAssertEqual(query["language"], "ko-KR")
        XCTAssertEqual(query["release_date_gte"], "2024-01-01")
        XCTAssertEqual(query["release_date_lte"], "2026-08-26")
        XCTAssertEqual(query["original_language"], "ko")
        XCTAssertEqual(query["origin_country"], "KR")
        XCTAssertEqual(query["certification_country"], "US")
        XCTAssertEqual(query["certification_gte"], "PG")
        XCTAssertEqual(query["certification_lte"], "R")
        XCTAssertEqual(query["runtime_gte"], "60")
        XCTAssertEqual(query["runtime_lte"], "180")
        XCTAssertEqual(query["vote_count_gte"], "100")
        XCTAssertEqual(query["region"], "VN")
        XCTAssertEqual(query["watch_region"], "VN")
        XCTAssertEqual(query["watch_providers"], "8|337")
        XCTAssertEqual(query["watch_monetization_types"], "buy|flatrate")
        XCTAssertEqual(query["include_adult"], "true")
    }

    func testBasicDiscoverFallsBackToV1AndOmitsAdvancedFields() async throws {
        URLProtocolStub.enqueue(status: 200, body: #"{"page":1,"total_pages":1,"results":[]}"#)
        let repository = RemoteCatalogRepository(client: makeClient())
        let filter = DiscoverFilter(
            genres: [28, 12],
            year: 1999,
            minimumRating: 7,
            sort: .rating,
            releaseDateFrom: "2026-01-01",
            watchProviderIDs: [8],
            includeAdult: true
        )

        _ = try await repository.discoverBasic(
            mediaType: .movie,
            filter: filter,
            page: 1,
            language: "en-US"
        )

        let url = try XCTUnwrap(URLProtocolStub.requests.first?.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: try XCTUnwrap(components.queryItems).map { ($0.name, $0.value) })
        XCTAssertEqual(url.path, "/api/v1/discover/movie")
        XCTAssertEqual(query["genre_ids"], "12,28")
        XCTAssertEqual(query["year"], "1999")
        XCTAssertEqual(query["vote_average_gte"], "7.0")
        XCTAssertEqual(query["sort_by"], "vote_average.desc")
        XCTAssertFalse(query.keys.contains("include_adult"))
        XCTAssertFalse(query.keys.contains("release_date_gte"))
        XCTAssertFalse(query.keys.contains("watch_providers"))
    }

    func testV2ConfigurationUsesRegionAndDecodesProviderOptions() async throws {
        URLProtocolStub.enqueue(status: 200, body: #"""
        {
          "countries": [{"iso_3166_1":"VN","english_name":"Vietnam","native_name":"Việt Nam"}],
          "languages": [{"iso_639_1":"vi","english_name":"Vietnamese","name":"Tiếng Việt"}],
          "watch_provider_regions": [{"iso_3166_1":"VN","english_name":"Vietnam","native_name":"Việt Nam"}],
          "region": "VN",
          "watch_providers": {
            "movie": [{"id":8,"name":"Netflix","logo_path":null,"display_priority":1}],
            "tv": []
          }
        }
        """#)
        let repository = RemoteCatalogRepository(client: makeClient())

        let value = try await repository.discoverConfiguration(language: "vi-VN", region: "VN")

        XCTAssertEqual(value.region, "VN")
        XCTAssertEqual(value.watchProviders?.movie.map(\.id), [8])
        let url = try XCTUnwrap(URLProtocolStub.requests.first?.url)
        XCTAssertEqual(url.path, "/api/v2/configuration")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(query["language"], "vi-VN")
        XCTAssertEqual(query["region"], "VN")
    }

    func testProfileProviderRegionsRequireAdvancedDiscoverCapability() async throws {
        let repository = RemoteCatalogRepository(client: makeClient())

        let unavailable = await loadProfileProviderRegions(
            catalog: repository,
            capabilities: nil,
            language: "vi-VN",
            region: "VN"
        )
        let disabled = await loadProfileProviderRegions(
            catalog: repository,
            capabilities: profileCapabilities(advancedDiscover: false),
            language: "vi-VN",
            region: "VN"
        )

        XCTAssertTrue(unavailable.isEmpty)
        XCTAssertTrue(disabled.isEmpty)
        XCTAssertTrue(URLProtocolStub.requests.isEmpty)

        URLProtocolStub.enqueue(status: 200, body: #"""
        {
          "countries": [], "languages": [],
          "watch_provider_regions": [
            {"iso_3166_1":"VN","english_name":"Vietnam","native_name":"Việt Nam"}
          ],
          "region": "VN"
        }
        """#)
        let enabled = await loadProfileProviderRegions(
            catalog: repository,
            capabilities: profileCapabilities(advancedDiscover: true),
            language: "vi-VN",
            region: "VN"
        )

        XCTAssertEqual(enabled.map(\.code), ["VN"])
        XCTAssertEqual(URLProtocolStub.requests.count, 1)
        XCTAssertEqual(URLProtocolStub.requests.first?.url?.path, "/api/v2/configuration")
    }

    func testV2FindExternalIDEncodesSourceAndDecodesDiscriminatedEntities() async throws {
        URLProtocolStub.enqueue(status: 200, body: #"""
        {
          "source":"imdb_id",
          "external_id":"tt0133093",
          "results":[{
            "entity_kind":"movie","id":603,"media_type":"movie","title":"The Matrix",
            "original_title":"The Matrix","overview":"","poster_path":null,"backdrop_path":null,
            "release_date":"1999-03-30","vote_average":8.2,"genre_ids":[28,878]
          }]
        }
        """#)
        let repository = RemoteCatalogRepository(client: makeClient())

        let response = try await repository.findExternalID(
            "tt0133093",
            source: .imdb,
            language: "vi-VN",
            includeAdult: false
        )

        XCTAssertEqual(response.externalID, "tt0133093")
        XCTAssertEqual(response.results.map(\.kind), [.movie])
        let request = try XCTUnwrap(URLProtocolStub.requests.first)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/api/v2/find/tt0133093")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "source" })?.value, "imdb_id")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "language" })?.value, "vi-VN")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "include_adult" })?.value, "false")
    }

    func testV2CreditDetailDecodesStablePersonAndTitleLinks() async throws {
        URLProtocolStub.enqueue(status: 200, body: #"""
        {
          "credit_id":"52fe425bc3a36847f80181c1","credit_type":"cast","department":"Acting",
          "job":"Actor","character":"Neo",
          "person_summary":{"entity_kind":"person","id":6384,"name":"Keanu Reeves","profile_path":null,
            "known_for_department":"Acting","popularity":1,"known_for":[]},
          "title_summary":{"entity_kind":"movie","id":603,"media_type":"movie","title":"The Matrix",
            "original_title":"The Matrix","overview":"","poster_path":null,"backdrop_path":null,
            "release_date":"1999-03-30","vote_average":8.2,"genre_ids":[28,878]}
        }
        """#)
        let repository = RemoteCatalogRepository(client: makeClient())

        let response = try await repository.credit(
            id: "52fe425bc3a36847f80181c1",
            language: "ko-KR",
            includeAdult: true
        )

        XCTAssertEqual(response.character, "Neo")
        XCTAssertEqual(response.personSummary?.name, "Keanu Reeves")
        XCTAssertEqual(response.titleSummary?.libraryKey, "movie:603")
        let request = try XCTUnwrap(URLProtocolStub.requests.first)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/api/v2/credits/52fe425bc3a36847f80181c1")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "language" })?.value, "ko-KR")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "include_adult" })?.value, "true")
    }

    func testInstallationClientIDIsStableAndRepairsInvalidStoredValue() async throws {
        let suite = "SmartMovieKitTests.\(UUID().uuidString)"
        let setupDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        setupDefaults.set("not-a-uuid", forKey: "SmartMovie.InstallationClientID")
        let provider = InstallationClientID(suiteName: suite)

        let first = await provider.clientID()
        let second = await provider.clientID()
        let persisted = UserDefaults(suiteName: suite)?.string(forKey: "SmartMovie.InstallationClientID")

        XCTAssertNotNil(UUID(uuidString: first))
        XCTAssertEqual(first, second)
        XCTAssertEqual(persisted, first)
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }

    private func assertError(_ expected: APIError) async {
        do {
            let _: TestPayload = try await makeClient().get("v1/test")
            XCTFail("Expected \(expected)")
        } catch {
            XCTAssertEqual(error as? APIError, expected)
        }
    }

    private func makeClient() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return APIClient(
            baseURL: URL(string: "https://catalog.example/api/")!,
            session: URLSession(configuration: configuration),
            clientIDProvider: FixedClientID(),
            sleep: { _ in }
        )
    }

    private func errorBody(code: String, requestID: String) -> String {
        #"{"error":{"code":"\#(code)","message":"Failure","request_id":"\#(requestID)"}}"#
    }

    private func profileCapabilities(advancedDiscover: Bool) -> CapabilitiesV2 {
        CapabilitiesV2(
            apiVersion: "v2",
            releaseTrain: "3.0.0",
            catalog: ["advanced_discover": advancedDiscover]
        )
    }
}

extension APIClientTests {
    func testEpisodeAccountStateUsesAuthenticatedGETAndDecodesHalfStepOrUnrated() async throws {
        let repository = RemoteAccountRepository(
            client: makeClient(), tokenStore: MemorySessionTokenStore(token: "unit-test-opaque-session")
        )
        for rated in ["false", "{\"value\":0.5}"] {
            URLProtocolStub.reset()
            URLProtocolStub.enqueue(status: 200, body:
                "{\"series_id\":1399,\"season_number\":0,\"episode_number\":2,\"rated\":\(rated),\"future\":true}")
            let state = try await repository.episodeAccountState(seriesID: 1399, season: 0, episode: 2)
            XCTAssertEqual(state.seriesId, 1399)
            XCTAssertEqual(state.seasonNumber, 0)
            XCTAssertEqual(state.episodeNumber, 2)
            XCTAssertEqual(state.ratingValue, rated == "false" ? nil : 0.5)
            let request = try XCTUnwrap(URLProtocolStub.requests.first)
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v2/account/state/episode/1399/0/2")
            XCTAssertNil(request.url?.query)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-test-opaque-session")
        }
    }

    func testRatingWirePreservesHalfStepsRemovalAndRetryIdentity() async throws {
        let repository = RemoteAccountRepository(
            client: makeClient(), tokenStore: MemorySessionTokenStore(token: "unit-test-opaque-session")
        )
        let targets: [(MediaType?, String)] = [(.movie, "movie/550"), (.tv, "tv/550"), (nil, "episode/1399/2/3")]
        let values: [Double?] = [0.5, 9.5, nil]
        for (mediaType, path) in targets {
            for value in values {
                URLProtocolStub.reset()
                let mutationID = UUID()
                URLProtocolStub.enqueue(status: 503, body: errorBody(code: "upstream_error", requestID: "rating-test"))
                URLProtocolStub.enqueue(status: 200, body: "{\"mutation_id\":\"\(mutationID)\",\"success\":true}")
                let result: MutationResult
                if let mediaType {
                    result = try await repository.setRating(mediaType: mediaType, id: 550, value: value, mutationID: mutationID)
                } else {
                    result = try await repository.setEpisodeRating(
                        seriesID: 1399, season: 2, episode: 3, value: value, mutationID: mutationID
                    )
                }
                XCTAssertEqual(result.mutationId, mutationID)
                XCTAssertEqual(URLProtocolStub.requests.count, 2)
                for request in URLProtocolStub.requests {
                    XCTAssertEqual(request.url?.path, "/api/v2/account/ratings/\(path)")
                    XCTAssertEqual(request.httpMethod, value == nil ? "DELETE" : "PUT")
                    XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), mutationID.uuidString.lowercased())
                    if let value {
                        let body = try requestBody(request)
                        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                        XCTAssertEqual(json["value"] as? Double, value)
                        XCTAssertEqual((json["mutation_id"] as? String).flatMap(UUID.init(uuidString:)), mutationID)
                    } else {
                        XCTAssertNil(request.httpBody)
                        XCTAssertNil(request.httpBodyStream)
                    }
                }
            }
        }
    }

    private func requestBody(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}

private struct TestPayload: Decodable, Sendable {
    let displayName: String
}

private actor FixedClientID: ClientIDProviding {
    func clientID() -> String { "unit-test-client" }
}

private class URLProtocolStub: URLProtocol, @unchecked Sendable {
    private struct Stub {
        let status: Int
        let headers: [String: String]
        let data: Data
    }

    nonisolated(unsafe) private static var stubs: [Stub] = []
    nonisolated(unsafe) private(set) static var requests: [URLRequest] = []
    private static let lock = NSLock()

    static func enqueue(status: Int, headers: [String: String] = [:], body: String) {
        lock.lock()
        stubs.append(Stub(status: status, headers: headers, data: Data(body.utf8)))
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        stubs = []
        requests = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let stub = Self.stubs.isEmpty ? nil : Self.stubs.removeFirst()
        Self.lock.unlock()

        guard let stub, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.status,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
