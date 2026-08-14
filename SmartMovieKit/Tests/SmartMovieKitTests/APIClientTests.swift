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
            sort: .releaseDate
        )

        let response = try await repository.discover(
            mediaType: .tv,
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
        XCTAssertEqual(query["genre_ids"], "12,28")
        XCTAssertEqual(query["year"], "2026")
        XCTAssertEqual(query["vote_average_gte"], "7.5")
        XCTAssertEqual(query["sort_by"], "primary_release_date.desc")
        XCTAssertEqual(query["language"], "ko-KR")
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
