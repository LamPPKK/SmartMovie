import SwiftData
import XCTest
@testable import SmartMovieKit

@MainActor
final class LibraryStoreTests: XCTestCase {
    func testFavoriteAndWatchlistAreIndependent() throws {
        let container = try LibraryStoreFactory.makeContainer(cloudKitContainerIdentifier: nil, inMemory: true)
        let repository = SwiftDataLibraryRepository(context: container.mainContext, now: { Date(timeIntervalSince1970: 100) })
        let title = sampleTitle()

        try repository.toggle(title, in: .favorites)
        XCTAssertTrue(try repository.contains(title, in: .favorites))
        XCTAssertFalse(try repository.contains(title, in: .watchlist))

        try repository.toggle(title, in: .watchlist)
        XCTAssertEqual(try repository.items(in: .favorites, mediaType: nil, sort: .recentlyAdded).count, 1)
        XCTAssertEqual(try repository.items(in: .watchlist, mediaType: nil, sort: .recentlyAdded).count, 1)

        try repository.toggle(title, in: .favorites)
        XCTAssertFalse(try repository.contains(title, in: .favorites))
        XCTAssertTrue(try repository.contains(title, in: .watchlist))
    }

    func testReconcileMergesCloudKitStyleDuplicates() throws {
        let container = try LibraryStoreFactory.makeContainer(cloudKitContainerIdentifier: nil, inMemory: true)
        let title = sampleTitle()
        let favorite = LibraryItem(summary: title, now: Date(timeIntervalSince1970: 100))
        favorite.isFavorite = true
        favorite.favoritedAt = Date(timeIntervalSince1970: 100)
        let watchlist = LibraryItem(summary: title, now: Date(timeIntervalSince1970: 200))
        watchlist.isWatchlisted = true
        watchlist.watchlistedAt = Date(timeIntervalSince1970: 200)
        container.mainContext.insert(favorite)
        container.mainContext.insert(watchlist)
        try container.mainContext.save()

        let repository = SwiftDataLibraryRepository(context: container.mainContext)
        try repository.reconcileDuplicates()

        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<SmartMovieKit.LibraryItem>()), 1)
        XCTAssertTrue(try repository.contains(title, in: .favorites))
        XCTAssertTrue(try repository.contains(title, in: .watchlist))
    }

    func testLibraryFiltersSortsAndRefreshesOfflineSnapshot() throws {
        let container = try LibraryStoreFactory.makeContainer(cloudKitContainerIdentifier: nil, inMemory: true)
        let clock = TestClock(Date(timeIntervalSince1970: 100))
        let repository = SwiftDataLibraryRepository(context: container.mainContext, now: { clock.now })
        let series = sampleTitle(id: 9, mediaType: .tv, title: "Zulu", releaseDate: "2020-01-01")
        let movie = sampleTitle(id: 10, mediaType: .movie, title: "Alpha", releaseDate: "2026-01-01")

        try repository.toggle(series, in: .favorites)
        clock.now = Date(timeIntervalSince1970: 200)
        try repository.toggle(movie, in: .favorites)

        XCTAssertEqual(
            try repository.items(in: .favorites, mediaType: nil, sort: .recentlyAdded).map(\.title.title),
            ["Alpha", "Zulu"]
        )
        XCTAssertEqual(
            try repository.items(in: .favorites, mediaType: nil, sort: .title).map(\.title.title),
            ["Alpha", "Zulu"]
        )
        XCTAssertEqual(
            try repository.items(in: .favorites, mediaType: nil, sort: .releaseDate).map(\.title.id),
            [10, 9]
        )
        XCTAssertEqual(
            try repository.items(in: .favorites, mediaType: .tv, sort: .title).map(\.title.id),
            [9]
        )

        clock.now = Date(timeIntervalSince1970: 300)
        let refreshedSeries = sampleTitle(
            id: 9,
            mediaType: .tv,
            title: "Beta",
            releaseDate: "2020-01-01",
            rating: 9.1
        )
        try repository.toggle(refreshedSeries, in: .watchlist)
        let offlineSnapshot = try XCTUnwrap(
            repository.items(in: .favorites, mediaType: .tv, sort: .title).first
        )
        XCTAssertEqual(offlineSnapshot.title.title, "Beta")
        XCTAssertEqual(offlineSnapshot.title.voteAverage, 9.1)
        XCTAssertTrue(offlineSnapshot.isFavorite)
        XCTAssertTrue(offlineSnapshot.isWatchlisted)
    }

    private func sampleTitle(
        id: Int = 9,
        mediaType: MediaType = .tv,
        title: String = "Series",
        releaseDate: String = "2026-01-01",
        rating: Double = 7.5
    ) -> TitleSummary {
        TitleSummary(
            id: id,
            mediaType: mediaType,
            title: title,
            originalTitle: title,
            overview: "Overview",
            releaseDate: releaseDate,
            voteAverage: rating
        )
    }
}

@MainActor
private final class TestClock {
    var now: Date
    init(_ now: Date) { self.now = now }
}
