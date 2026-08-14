import Foundation
import SwiftData

@Model
public final class LibraryItem {
    public var libraryKey: String = ""
    public var tmdbID: Int = 0
    public var mediaTypeRaw: String = MediaType.movie.rawValue
    public var title: String = ""
    public var originalTitle: String = ""
    public var overview: String = ""
    public var posterPath: String?
    public var backdropPath: String?
    public var releaseDate: String?
    public var voteAverage: Double = 0
    public var isFavorite: Bool = false
    public var isWatchlisted: Bool = false
    public var favoritedAt: Date?
    public var watchlistedAt: Date?
    public var updatedAt: Date = Date.distantPast

    public init(summary: TitleSummary, now: Date = .now) {
        libraryKey = summary.libraryKey
        tmdbID = summary.id
        mediaTypeRaw = summary.mediaType.rawValue
        title = summary.title
        originalTitle = summary.originalTitle
        overview = summary.overview
        posterPath = summary.posterPath
        backdropPath = summary.backdropPath
        releaseDate = summary.releaseDate
        voteAverage = summary.voteAverage
        updatedAt = now
    }
}

public struct LibrarySnapshot: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: TitleSummary
    public let isFavorite: Bool
    public let isWatchlisted: Bool
    public let favoritedAt: Date?
    public let watchlistedAt: Date?
    public let updatedAt: Date
}

public enum LibraryStoreFactory {
    public static func makeContainer(
        cloudKitContainerIdentifier: String? = "iCloud.LamNDT.SmartMovie",
        inMemory: Bool = false
    ) throws -> ModelContainer {
        let cloudKitDatabase: ModelConfiguration.CloudKitDatabase = if inMemory || cloudKitContainerIdentifier == nil {
            .none
        } else {
            .private(cloudKitContainerIdentifier!)
        }
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: cloudKitDatabase
        )
        return try ModelContainer(for: LibraryItem.self, configurations: configuration)
    }
}

@MainActor
public final class SwiftDataLibraryRepository: LibraryRepository {
    private let context: ModelContext
    private let now: () -> Date

    public init(context: ModelContext, now: @escaping () -> Date = { .now }) {
        self.context = context
        self.now = now
    }

    public func contains(_ title: TitleSummary, in collection: LibraryCollection) throws -> Bool {
        guard let item = try items(forKey: title.libraryKey).max(by: { $0.updatedAt < $1.updatedAt }) else {
            return false
        }
        return collection == .favorites ? item.isFavorite : item.isWatchlisted
    }

    public func toggle(_ title: TitleSummary, in collection: LibraryCollection) throws {
        let existing = try items(forKey: title.libraryKey)
        let item = existing.max(by: { $0.updatedAt < $1.updatedAt }) ?? LibraryItem(summary: title, now: now())
        if item.modelContext == nil { context.insert(item) }
        refreshSnapshot(item, from: title)
        let timestamp = now()
        switch collection {
        case .favorites:
            item.isFavorite.toggle()
            item.favoritedAt = item.isFavorite ? timestamp : nil
        case .watchlist:
            item.isWatchlisted.toggle()
            item.watchlistedAt = item.isWatchlisted ? timestamp : nil
        }
        item.updatedAt = timestamp
        for duplicate in existing where duplicate !== item {
            merge(duplicate, into: item)
            context.delete(duplicate)
        }
        try context.save()
    }

    public func items(
        in collection: LibraryCollection,
        mediaType: MediaType?,
        sort: LibrarySort
    ) throws -> [LibrarySnapshot] {
        let all = try context.fetch(FetchDescriptor<LibraryItem>())
        let deduplicated = Dictionary(grouping: all, by: \.libraryKey).compactMap { _, values in
            values.max(by: { $0.updatedAt < $1.updatedAt })
        }
        let filtered = deduplicated.filter { item in
            let included = collection == .favorites ? item.isFavorite : item.isWatchlisted
            return included && (mediaType == nil || item.mediaTypeRaw == mediaType?.rawValue)
        }
        let ordered = filtered.sorted { lhs, rhs in
            switch sort {
            case .recentlyAdded:
                let left = collection == .favorites ? lhs.favoritedAt : lhs.watchlistedAt
                let right = collection == .favorites ? rhs.favoritedAt : rhs.watchlistedAt
                return (left ?? .distantPast) > (right ?? .distantPast)
            case .title:
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            case .releaseDate:
                return (lhs.releaseDate ?? "") > (rhs.releaseDate ?? "")
            }
        }
        return ordered.map(snapshot)
    }

    public func reconcileDuplicates() throws {
        let all = try context.fetch(FetchDescriptor<LibraryItem>())
        for values in Dictionary(grouping: all, by: \.libraryKey).values where values.count > 1 {
            guard let winner = values.max(by: { $0.updatedAt < $1.updatedAt }) else { continue }
            for duplicate in values where duplicate !== winner {
                merge(duplicate, into: winner)
                context.delete(duplicate)
            }
        }
        try context.save()
    }

    private func items(forKey key: String) throws -> [LibraryItem] {
        let descriptor = FetchDescriptor<LibraryItem>(predicate: #Predicate { $0.libraryKey == key })
        return try context.fetch(descriptor)
    }

    private func refreshSnapshot(_ item: LibraryItem, from title: TitleSummary) {
        item.title = title.title
        item.originalTitle = title.originalTitle
        item.overview = title.overview
        item.posterPath = title.posterPath
        item.backdropPath = title.backdropPath
        item.releaseDate = title.releaseDate
        item.voteAverage = title.voteAverage
    }

    private func merge(_ source: LibraryItem, into target: LibraryItem) {
        if source.updatedAt > target.updatedAt {
            target.title = source.title
            target.originalTitle = source.originalTitle
            target.overview = source.overview
            target.posterPath = source.posterPath
            target.backdropPath = source.backdropPath
            target.releaseDate = source.releaseDate
            target.voteAverage = source.voteAverage
            target.updatedAt = source.updatedAt
        }
        if source.isFavorite {
            target.isFavorite = true
            target.favoritedAt = maxDate(target.favoritedAt, source.favoritedAt)
        }
        if source.isWatchlisted {
            target.isWatchlisted = true
            target.watchlistedAt = maxDate(target.watchlistedAt, source.watchlistedAt)
        }
    }

    private func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (left?, right?): max(left, right)
        case let (left?, nil): left
        case let (nil, right?): right
        case (nil, nil): nil
        }
    }

    private func snapshot(_ item: LibraryItem) -> LibrarySnapshot {
        let mediaType = MediaType(rawValue: item.mediaTypeRaw) ?? .movie
        return LibrarySnapshot(
            id: item.libraryKey,
            title: TitleSummary(
                id: item.tmdbID,
                mediaType: mediaType,
                title: item.title,
                originalTitle: item.originalTitle,
                overview: item.overview,
                posterPath: item.posterPath,
                backdropPath: item.backdropPath,
                releaseDate: item.releaseDate,
                voteAverage: item.voteAverage
            ),
            isFavorite: item.isFavorite,
            isWatchlisted: item.isWatchlisted,
            favoritedAt: item.favoritedAt,
            watchlistedAt: item.watchlistedAt,
            updatedAt: item.updatedAt
        )
    }
}
