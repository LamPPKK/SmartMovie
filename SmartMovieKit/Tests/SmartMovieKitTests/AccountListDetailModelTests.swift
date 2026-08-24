import XCTest
@testable import SmartMovieKit

@MainActor
final class AccountListDetailModelTests: XCTestCase {
    func testLoadsMixedPagesFiltersAdultAndDeduplicates() async {
        let movie = title(id: 1, type: .movie)
        let adult = title(id: 2, type: .movie, adult: true)
        let series = title(id: 3, type: .tv)
        let repository = ListStub(pages: [
            UserList(
                id: 7,
                name: "Mixed",
                description: "Movie and TV",
                isPublic: false,
                page: 1,
                totalPages: 2,
                results: [movie, adult]
            ),
            UserList(
                id: 7,
                name: "Mixed",
                description: "Movie and TV",
                isPublic: false,
                page: 2,
                totalPages: 2,
                results: [movie, series]
            )
        ])
        let model = AccountListDetailModel(list: summary)

        await model.load(language: "vi-VN", includeAdult: false, pending: { [] }, repository: repository)
        await model.loadMore(language: "vi-VN", includeAdult: false, pending: { [] }, repository: repository)

        XCTAssertEqual(model.list.results.map(\.libraryKey), ["movie:1", "tv:3"])
        XCTAssertFalse(model.canLoadMore)
        let requests = await repository.requests
        XCTAssertEqual(requests, [ListRequest(page: 1, language: "vi-VN"), ListRequest(page: 2, language: "vi-VN")])
    }

    func testSearchExcludesAdultExistingAndDuplicateTitles() async {
        let existing = title(id: 1, type: .movie)
        let series = title(id: 3, type: .tv)
        let model = AccountListDetailModel(list: UserList(
            id: 7,
            name: "Mixed",
            description: "",
            isPublic: false,
            results: [existing]
        ))
        let repository = SearchStub(results: [
            existing,
            title(id: 2, type: .movie, adult: true),
            series,
            series
        ])
        model.searchQuery = "story"

        await model.search(language: "ja-JP", includeAdult: false, repository: repository)

        XCTAssertEqual(model.searchResults.map(\.libraryKey), ["tv:3"])
        let request = await repository.request
        XCTAssertEqual(request, SearchRequest(query: "story", language: "ja-JP"))
    }

    func testAppliesOptimisticMetadataAndItemMutations() {
        let movie = title(id: 1, type: .movie)
        let series = title(id: 3, type: .tv)
        let model = AccountListDetailModel(list: UserList(
            id: 7,
            name: "Old",
            description: "Old description",
            isPublic: false,
            results: [movie]
        ))

        model.name = " Weekend "
        model.listDescription = " Ready "
        model.isPublic = true
        model.applyMetadata()
        model.add(series)
        model.remove(movie)

        XCTAssertEqual(model.list.name, "Weekend")
        XCTAssertEqual(model.list.description, "Ready")
        XCTAssertTrue(model.list.public)
        XCTAssertEqual(model.list.results.map(\.libraryKey), ["tv:3"])
    }

    func testPendingSnapshotsWinWhenRemoteListReloads() async {
        let movie = title(id: 1, type: .movie)
        let series = title(id: 3, type: .tv)
        let pending = [
            AccountPendingMutation(
                accountID: 42,
                payload: .mutateListItems(
                    listID: 7,
                    items: [UserListItemMutation(mediaType: .movie, mediaId: movie.id)],
                    titles: [movie],
                    remove: true
                ),
                createdAt: Date(timeIntervalSince1970: 1)
            ),
            AccountPendingMutation(
                accountID: 42,
                payload: .mutateListItems(
                    listID: 7,
                    items: [UserListItemMutation(mediaType: .tv, mediaId: series.id)],
                    titles: [series],
                    remove: false
                ),
                createdAt: Date(timeIntervalSince1970: 2)
            )
        ]
        let repository = ListStub(pages: [UserList(
            id: 7,
            name: "Remote",
            description: "",
            isPublic: false,
            page: 1,
            totalPages: 1,
            results: [movie]
        )])
        let model = AccountListDetailModel(list: summary)

        await model.load(language: "en-US", includeAdult: false, pending: { pending }, repository: repository)

        XCTAssertEqual(model.list.results.map(\.libraryKey), ["tv:3"])
    }

    func testLockingAdultFiltersCachedDetailAndSearchWithoutNetwork() async {
        let adult = title(id: 2, type: .movie, adult: true)
        let model = AccountListDetailModel(list: UserList(
            id: 7,
            name: "Mixed",
            description: "",
            isPublic: false,
            results: [adult]
        ))
        model.searchQuery = "adult"
        await model.search(language: "en-US", includeAdult: true, repository: SearchStub(results: [adult]))

        model.applyAdultVisibility(includeAdult: false)

        XCTAssertTrue(model.list.results.isEmpty)
        XCTAssertTrue(model.searchResults.isEmpty)
    }

    func testLockedReloadDoesNotRestorePendingAdultSnapshot() async {
        let adult = title(id: 2, type: .movie, adult: true)
        let pending = [AccountPendingMutation(
            accountID: 42,
            payload: .mutateListItems(
                listID: 7,
                items: [UserListItemMutation(mediaType: .movie, mediaId: adult.id)],
                titles: [adult],
                remove: false
            )
        )]
        let repository = ListStub(pages: [UserList(
            id: 7,
            name: "Mixed",
            description: "",
            isPublic: false,
            page: 1,
            totalPages: 1,
            results: []
        )])
        let model = AccountListDetailModel(list: summary)

        await model.load(language: "en-US", includeAdult: false, pending: { pending }, repository: repository)

        XCTAssertTrue(model.list.results.isEmpty)
    }

    func testLockInvalidatesAdultSearchAlreadyInFlight() async {
        let adult = title(id: 2, type: .movie, adult: true)
        let model = AccountListDetailModel(list: summary)
        model.searchQuery = "adult"
        let task = Task {
            await model.search(
                language: "en-US",
                includeAdult: true,
                repository: DelayedSearchStub(results: [adult])
            )
        }
        try? await Task.sleep(for: .milliseconds(10))

        model.applyAdultVisibility(includeAdult: false)
        await task.value

        XCTAssertTrue(model.searchResults.isEmpty)
        XCTAssertFalse(model.isSearching)
    }

    private var summary: UserList {
        UserList(id: 7, name: "Mixed", description: "", isPublic: false, results: [])
    }

    private func title(id: Int, type: MediaType, adult: Bool = false) -> TitleSummary {
        TitleSummary(
            id: id,
            mediaType: type,
            title: "Title \(id)",
            originalTitle: "Title \(id)",
            overview: "",
            isAdult: adult
        )
    }
}

private struct ListRequest: Equatable, Sendable {
    let page: Int
    let language: String
}

private actor ListStub: AccountListLoading {
    private let pages: [UserList]
    private(set) var requests: [ListRequest] = []

    init(pages: [UserList]) {
        self.pages = pages
    }

    func list(id: Int, page: Int, language: String) throws -> UserList {
        requests.append(ListRequest(page: page, language: language))
        guard id == 7, pages.indices.contains(page - 1) else { throw APIError.invalidResponse }
        return pages[page - 1]
    }
}

private struct SearchRequest: Equatable, Sendable {
    let query: String
    let language: String
}

private actor SearchStub: TitleSearching {
    private let results: [TitleSummary]
    private(set) var request: SearchRequest?

    init(results: [TitleSummary]) {
        self.results = results
    }

    func search(
        query: String,
        scope: SearchScope,
        page: Int,
        language: String
    ) throws -> PagedResult<TitleSummary> {
        request = SearchRequest(query: query, language: language)
        return PagedResult(page: 1, totalPages: 1, results: results)
    }
}

private actor DelayedSearchStub: TitleSearching {
    private let results: [TitleSummary]

    init(results: [TitleSummary]) {
        self.results = results
    }

    func search(
        query: String,
        scope: SearchScope,
        page: Int,
        language: String
    ) async throws -> PagedResult<TitleSummary> {
        try await Task.sleep(for: .milliseconds(50))
        return PagedResult(page: 1, totalPages: 1, results: results)
    }
}
