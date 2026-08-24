import XCTest
@testable import SmartMovieKit

@MainActor
final class AccountRecommendationsModelTests: XCTestCase {
    func testFiltersAdultContentAndDeduplicatesPaginatedResults() async {
        let model = AccountRecommendationsModel()
        let safe = title(id: 1, adult: false)
        let adult = title(id: 2, adult: true)
        let repository = RecommendationsStub(pages: [
            .movie: [
                PagedResult(page: 1, totalPages: 2, results: [safe, adult]),
                PagedResult(page: 2, totalPages: 2, results: [safe, title(id: 3, adult: false)])
            ]
        ])

        await model.reload(language: "vi-VN", includeAdult: false, repository: repository)
        await model.loadMore(language: "vi-VN", includeAdult: false, repository: repository)

        guard case .loaded(let values) = model.state else { return XCTFail("Expected recommendations") }
        XCTAssertEqual(values.map(\.id), [1, 3])
        XCTAssertFalse(model.canLoadMore)
        let requests = await repository.recordedRequests()
        XCTAssertEqual(requests, [
            RecommendationRequest(mediaType: .movie, page: 1, language: "vi-VN"),
            RecommendationRequest(mediaType: .movie, page: 2, language: "vi-VN")
        ])
    }

    func testSwitchingMediaTypeResetsAndLoadsTV() async {
        let model = AccountRecommendationsModel()
        let repository = RecommendationsStub(pages: [
            .tv: [PagedResult(page: 1, totalPages: 1, results: [title(id: 4, type: .tv, adult: true)])]
        ])
        model.select(.tv)

        await model.reload(language: "ja-JP", includeAdult: true, repository: repository)

        guard case .loaded(let values) = model.state else { return XCTFail("Expected TV recommendations") }
        XCTAssertEqual(values.map(\.libraryKey), ["tv:4"])
    }

    private func title(id: Int, type: MediaType = .movie, adult: Bool) -> TitleSummary {
        TitleSummary(id: id, mediaType: type, title: "Title \(id)", originalTitle: "Title \(id)", overview: "", isAdult: adult)
    }
}

private struct RecommendationRequest: Equatable, Sendable {
    let mediaType: MediaType
    let page: Int
    let language: String
}

private actor RecommendationsStub: AccountRecommendationsLoading {
    private let pages: [MediaType: [PagedResult<TitleSummary>]]
    private var requests: [RecommendationRequest] = []

    init(pages: [MediaType: [PagedResult<TitleSummary>]]) {
        self.pages = pages
    }

    func recommendations(
        mediaType: MediaType,
        page: Int,
        language: String
    ) throws -> PagedResult<TitleSummary> {
        requests.append(RecommendationRequest(mediaType: mediaType, page: page, language: language))
        guard let result = pages[mediaType]?[safe: page - 1] else { throw APIError.invalidResponse }
        return result
    }

    func recordedRequests() -> [RecommendationRequest] { requests }
}

private extension Array {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
