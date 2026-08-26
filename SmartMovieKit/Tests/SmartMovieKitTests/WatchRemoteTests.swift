import Foundation
import XCTest
@testable import SmartMovieKit

@MainActor
final class WatchRemoteTests: XCTestCase {
    func testCoordinatorPresentsRemoteIntentAndTracksLibraryChanges() throws {
        let coordinator = WatchRemoteCoordinator()
        let title = TitleSummary(
            id: 550,
            mediaType: .movie,
            title: "Fight Club",
            originalTitle: "Fight Club",
            overview: ""
        )

        coordinator.present(title: title, playsTrailer: true)

        let presentation = try XCTUnwrap(coordinator.presentation)
        XCTAssertEqual(presentation.title, title)
        XCTAssertTrue(presentation.playsTrailer)
        XCTAssertEqual(coordinator.libraryRevision, 0)

        coordinator.libraryDidChange()
        XCTAssertEqual(coordinator.libraryRevision, 1)

        coordinator.dismissPresentation()
        XCTAssertNil(coordinator.presentation)
    }

    func testRemoteContextCarriesWatchDisplayAndLibraryState() {
        let title = TitleSummary(
            id: 1399,
            mediaType: .tv,
            title: "Game of Thrones",
            originalTitle: "Game of Thrones",
            overview: "",
            posterPath: "/poster.jpg",
            releaseDate: "2011-04-17",
            voteAverage: 8.5
        )
        let context = WatchRemoteContext(
            title: title,
            artworkURL: URL(string: "https://image.tmdb.org/t/p/w500/poster.jpg"),
            isFavorite: true,
            isWatchlisted: false,
            hasTrailer: true
        )

        XCTAssertEqual(context.title.libraryKey, "tv:1399")
        XCTAssertEqual(context.title.releaseYear, "2011")
        XCTAssertTrue(context.isFavorite)
        XCTAssertFalse(context.isWatchlisted)
        XCTAssertTrue(context.hasTrailer)
        XCTAssertEqual(context.contextKey, "tv:1399")
        XCTAssertTrue(context.supportsLibraryActions)
    }

    func testEpisodeContextUsesStableIdentityAndOpensEpisodePresentation() throws {
        let series = TitleSummary(
            id: 1399,
            mediaType: .tv,
            title: "Game of Thrones",
            originalTitle: "Game of Thrones",
            overview: ""
        )
        let episode = EpisodeSummary(
            id: 63056,
            seriesId: 1399,
            seasonNumber: 1,
            episodeNumber: 1,
            name: "Winter Is Coming",
            overview: "",
            stillPath: "/still.jpg",
            airDate: "2011-04-17",
            runtimeMinutes: 62,
            voteAverage: 8.5
        )
        let context = WatchRemoteContext(
            title: series,
            episode: episode,
            artworkURL: URL(string: "https://image.tmdb.org/t/p/w780/still.jpg"),
            isFavorite: false,
            isWatchlisted: false,
            hasTrailer: false
        )

        XCTAssertEqual(context.contextKey, "episode:1399:1:1")
        XCTAssertFalse(context.supportsLibraryActions)

        let coordinator = WatchRemoteCoordinator()
        coordinator.presentEpisode(series: series, episode: episode)
        let presentation = try XCTUnwrap(coordinator.presentation)
        XCTAssertEqual(presentation.title, series)
        XCTAssertEqual(presentation.episode, episode)
        XCTAssertFalse(presentation.playsTrailer)
    }
}
