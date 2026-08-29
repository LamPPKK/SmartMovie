import SwiftData
import XCTest
@testable import SmartMovieKit

@MainActor
final class EpisodeProgressStoreTests: XCTestCase {
    func testEpisodeKeysAreStableAndProgressIsIndependentBySeriesAndSeason() throws {
        let (container, repository) = try makeRepository()
        let first = EpisodeWatchKey(seriesID: 11, seasonNumber: 1, episodeNumber: 2)
        let otherSeason = EpisodeWatchKey(seriesID: 11, seasonNumber: 2, episodeNumber: 2)
        let otherSeries = EpisodeWatchKey(seriesID: 12, seasonNumber: 1, episodeNumber: 2)

        XCTAssertEqual(first.rawValue, "11:1:2")
        try repository.setWatched(true, for: first)
        try repository.setWatched(true, for: otherSeason)
        try repository.setWatched(true, for: otherSeries)

        XCTAssertTrue(try repository.isWatched(first))
        XCTAssertEqual(try repository.watchedEpisodeNumbers(seriesID: 11, seasonNumber: 1), [2])
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<EpisodeWatchRecord>()), 3)

        try repository.setWatched(false, for: first)
        XCTAssertFalse(try repository.isWatched(first))
        XCTAssertEqual(try repository.watchedEpisodeNumbers(seriesID: 11, seasonNumber: 1), [])
        XCTAssertEqual(try repository.watchedEpisodeNumbers(seriesID: 11, seasonNumber: 2), [2])
        XCTAssertEqual(try repository.watchedEpisodeNumbers(seriesID: 12, seasonNumber: 1), [2])
    }

    func testSeasonMutationIsIdempotentAndDoesNotTouchUnlistedEpisodes() throws {
        let (container, repository) = try makeRepository()
        let special = EpisodeWatchKey(seriesID: 11, seasonNumber: 0, episodeNumber: 1)
        try repository.setWatched(true, for: special)

        try repository.setSeasonWatched(true, seriesID: 11, seasonNumber: 1, episodeNumbers: [1, 2, 2, 3])
        try repository.setSeasonWatched(true, seriesID: 11, seasonNumber: 1, episodeNumbers: [1, 2, 3])
        XCTAssertEqual(try repository.watchedEpisodeNumbers(seriesID: 11, seasonNumber: 1), [1, 2, 3])
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<EpisodeWatchRecord>()), 4)

        try repository.setSeasonWatched(false, seriesID: 11, seasonNumber: 1, episodeNumbers: [1, 3])
        XCTAssertEqual(try repository.watchedEpisodeNumbers(seriesID: 11, seasonNumber: 1), [2])
        XCTAssertTrue(try repository.isWatched(special))
    }

    func testDuplicateReconciliationKeepsNewestRecord() throws {
        let (container, repository) = try makeRepository()
        let key = EpisodeWatchKey(seriesID: 11, seasonNumber: 1, episodeNumber: 2)
        let old = EpisodeWatchRecord(key: key, now: Date(timeIntervalSince1970: 100))
        let newest = EpisodeWatchRecord(key: key, now: Date(timeIntervalSince1970: 200))
        container.mainContext.insert(old)
        container.mainContext.insert(newest)
        try container.mainContext.save()

        try repository.reconcileDuplicates()

        let records = try container.mainContext.fetch(FetchDescriptor<EpisodeWatchRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.watchedAt, Date(timeIntervalSince1970: 200))
    }

    func testProgressWritesPreserveExistingFavoriteAndWatchlistRows() throws {
        let container = try LibraryStoreFactory.makeContainer(cloudKitContainerIdentifier: nil, inMemory: true)
        let library = SwiftDataLibraryRepository(context: container.mainContext)
        let progress = SwiftDataEpisodeProgressRepository(context: container.mainContext)
        let series = TitleSummary(
            id: 11, mediaType: .tv, title: "Series", originalTitle: "Series",
            overview: "Overview", releaseDate: "2026-01-01", voteAverage: 8
        )
        try library.toggle(series, in: .favorites)
        try library.toggle(series, in: .watchlist)

        try progress.setSeasonWatched(true, seriesID: 11, seasonNumber: 1, episodeNumbers: [1, 2])

        XCTAssertTrue(try library.contains(series, in: .favorites))
        XCTAssertTrue(try library.contains(series, in: .watchlist))
        XCTAssertEqual(try progress.watchedEpisodeNumbers(seriesID: 11, seasonNumber: 1), [1, 2])
    }

    func testAddingProgressSchemaMigratesExistingLibraryWithoutDataLoss() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SmartMovieEpisodeProgress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("library.store")
        let title = TitleSummary(
            id: 11, mediaType: .tv, title: "Legacy Series", originalTitle: "Legacy Series",
            overview: "Overview", releaseDate: "2025-01-01", voteAverage: 7.5
        )

        try writeLegacyLibrary(title: title, storeURL: storeURL)

        let key = EpisodeWatchKey(seriesID: 11, seasonNumber: 1, episodeNumber: 1)
        try migrateLibraryAndWriteProgress(title: title, key: key, storeURL: storeURL)

        let schema = Schema([LibraryItem.self, LibraryOutboxItem.self, EpisodeWatchRecord.self])
        let reopened = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        )
        let reopenedLibrary = SwiftDataLibraryRepository(context: reopened.mainContext)
        let reopenedProgress = SwiftDataEpisodeProgressRepository(context: reopened.mainContext)
        XCTAssertTrue(try reopenedLibrary.contains(title, in: .favorites))
        XCTAssertTrue(try reopenedLibrary.contains(title, in: .watchlist))
        XCTAssertTrue(try reopenedProgress.isWatched(key))
    }

    private func makeRepository() throws -> (ModelContainer, SwiftDataEpisodeProgressRepository) {
        let container = try LibraryStoreFactory.makeContainer(cloudKitContainerIdentifier: nil, inMemory: true)
        return (container, SwiftDataEpisodeProgressRepository(context: container.mainContext))
    }

    private func writeLegacyLibrary(title: TitleSummary, storeURL: URL) throws {
        let schema = Schema([LibraryItem.self, LibraryOutboxItem.self])
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let legacy = try ModelContainer(for: schema, configurations: configuration)
        let item = LibraryItem(summary: title)
        item.isFavorite = true
        item.isWatchlisted = true
        legacy.mainContext.insert(item)
        try legacy.mainContext.save()
    }

    private func migrateLibraryAndWriteProgress(
        title: TitleSummary,
        key: EpisodeWatchKey,
        storeURL: URL
    ) throws {
        let schema = Schema([LibraryItem.self, LibraryOutboxItem.self, EpisodeWatchRecord.self])
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let migrated = try ModelContainer(for: schema, configurations: configuration)
        let library = SwiftDataLibraryRepository(context: migrated.mainContext)
        let progress = SwiftDataEpisodeProgressRepository(context: migrated.mainContext)
        XCTAssertTrue(try library.contains(title, in: .favorites))
        XCTAssertTrue(try library.contains(title, in: .watchlist))
        XCTAssertFalse(try progress.isWatched(key))
        try progress.setWatched(true, for: key)
    }
}
