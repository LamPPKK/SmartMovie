import XCTest
@testable import SmartMovieKit

final class CatalogEditorialPresentationTests: XCTestCase {
    func testReviewsRemoveBlankContentAndDuplicateIDsWithoutReordering() {
        let values = [
            review(id: "first", content: "First review"),
            review(id: "blank", content: " "),
            review(id: "first", content: "Duplicate"),
            review(id: "second", content: "Second review"),
            review(id: "third", content: "Third review"),
            review(id: "fourth", content: "Fourth review"),
            review(id: "fifth", content: "Fifth review")
        ]

        XCTAssertEqual(
            CatalogEditorialPresentation.reviews(values).map(\.id),
            ["first", "second", "third", "fourth"]
        )
    }

    func testTitlesExcludeCurrentTitleAndDeduplicateLibraryKeys() {
        let values = [
            title(id: 10, type: .movie),
            title(id: 20, type: .movie),
            title(id: 20, type: .movie),
            title(id: 20, type: .tv),
            title(id: 30, type: .movie, isAdult: true)
        ]

        XCTAssertEqual(
            CatalogEditorialPresentation.titles(values, excluding: "movie:10").map(\.libraryKey),
            ["movie:20", "tv:20"]
        )
        XCTAssertEqual(
            CatalogEditorialPresentation.titles(
                values,
                excluding: "movie:10",
                includeAdult: true
            ).map(\.libraryKey),
            ["movie:20", "tv:20", "movie:30"]
        )
    }

    private func review(id: String, content: String) -> Review {
        Review(
            id: id,
            author: "Reviewer",
            content: content,
            createdAt: nil,
            updatedAt: nil,
            url: nil,
            avatarPath: nil,
            rating: nil
        )
    }

    private func title(id: Int, type: MediaType, isAdult: Bool = false) -> TitleSummary {
        TitleSummary(
            id: id,
            mediaType: type,
            title: "Title \(id)",
            originalTitle: "Title \(id)",
            overview: "",
            posterPath: nil,
            backdropPath: nil,
            releaseDate: nil,
            voteAverage: 0,
            genreIDs: [],
            isAdult: isAdult
        )
    }
}
