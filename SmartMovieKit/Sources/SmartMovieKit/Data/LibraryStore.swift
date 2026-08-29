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
    public var isAdult: Bool = false
    public var isFavorite: Bool = false
    public var isWatchlisted: Bool = false
    public var favoritedAt: Date?
    public var watchlistedAt: Date?
    public var updatedAt: Date = Date.distantPast
    public var syncOriginRaw: String = LibrarySyncOrigin.local.rawValue
    public var favoritePending: Bool = false
    public var watchlistPending: Bool = false
    public var remoteRevision: String?
    public var accountID: Int?

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
        isAdult = summary.isAdult
        updatedAt = now
    }
}

@Model
public final class LibraryOutboxItem {
    public var mutationID: UUID = UUID()
    public var libraryKey: String = ""
    public var mediaTypeRaw: String = MediaType.movie.rawValue
    public var mediaID: Int = 0
    public var collectionRaw: String = LibraryCollection.favorites.rawValue
    public var enabled: Bool = false
    public var accountID: Int = 0
    public var createdAt: Date = Date.distantPast
    public var attemptCount: Int = 0
    public var lastAttemptAt: Date?
    public var lastError: String?

    public init(
        title: TitleSummary,
        collection: LibraryCollection,
        enabled: Bool,
        accountID: Int,
        now: Date
    ) {
        libraryKey = title.libraryKey
        mediaTypeRaw = title.mediaType.rawValue
        mediaID = title.id
        collectionRaw = collection.rawValue
        self.enabled = enabled
        self.accountID = accountID
        createdAt = now
    }
}

public enum LibrarySyncOrigin: String, Codable, Sendable {
    case local
    case tmdb
    case merged
}

public struct LibraryPendingMutation: Identifiable, Sendable {
    public let id: UUID
    public let libraryKey: String
    public let mediaType: MediaType
    public let mediaID: Int
    public let collection: LibraryCollection
    public let enabled: Bool
    public let accountID: Int
    public let attemptCount: Int
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
        return try ModelContainer(
            for: LibraryItem.self, LibraryOutboxItem.self, EpisodeWatchRecord.self,
            configurations: configuration
        )
    }
}

@MainActor
public final class SwiftDataLibraryRepository: LibraryRepository {
    private let context: ModelContext
    private let now: () -> Date
    private var activeAccountID: Int?

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
        if let accountID = activeAccountID {
            let pending = LibraryOutboxItem(
                title: title,
                collection: collection,
                enabled: collection == .favorites ? item.isFavorite : item.isWatchlisted,
                accountID: accountID,
                now: timestamp
            )
            context.insert(pending)
            item.accountID = accountID
            item.syncOriginRaw = LibrarySyncOrigin.merged.rawValue
            if collection == .favorites { item.favoritePending = true } else { item.watchlistPending = true }
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
        item.isAdult = title.isAdult
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
                voteAverage: item.voteAverage,
                isAdult: item.isAdult
            ),
            isFavorite: item.isFavorite,
            isWatchlisted: item.isWatchlisted,
            favoritedAt: item.favoritedAt,
            watchlistedAt: item.watchlistedAt,
            updatedAt: item.updatedAt
        )
    }
}

extension SwiftDataLibraryRepository: LibrarySyncRepository {
    public func activateAccount(_ accountID: Int) throws {
        activeAccountID = accountID
        let items = try context.fetch(FetchDescriptor<LibraryItem>())
        for item in items where item.accountID == nil { item.accountID = accountID }
        try context.save()
    }

    public func deactivateAccount(removeAccountData: Bool) throws {
        let accountID = activeAccountID
        activeAccountID = nil
        if removeAccountData, let accountID {
            let items = try context.fetch(FetchDescriptor<LibraryItem>())
            for item in items where item.accountID == accountID {
                context.delete(item)
            }
            let outbox = try context.fetch(FetchDescriptor<LibraryOutboxItem>())
            for mutation in outbox where mutation.accountID == accountID { context.delete(mutation) }
        } else {
            let items = try context.fetch(FetchDescriptor<LibraryItem>())
            for item in items {
                item.accountID = nil
                item.syncOriginRaw = LibrarySyncOrigin.local.rawValue
                item.favoritePending = false
                item.watchlistPending = false
            }
            let outbox = try context.fetch(FetchDescriptor<LibraryOutboxItem>())
            for mutation in outbox { context.delete(mutation) }
        }
        try context.save()
    }

    public func mergeRemote(
        _ remote: [TitleSummary],
        collection: LibraryCollection,
        mediaType: MediaType,
        accountID: Int
    ) throws {
        activeAccountID = accountID
        let remoteKeys = Set(remote.map(\.libraryKey))
        for title in remote {
            let matches = try items(forKey: title.libraryKey)
            let item = matches.max(by: { $0.updatedAt < $1.updatedAt }) ?? LibraryItem(summary: title, now: now())
            if item.modelContext == nil { context.insert(item) }
            refreshSnapshot(item, from: title)
            item.accountID = accountID
            item.syncOriginRaw = item.syncOriginRaw == LibrarySyncOrigin.local.rawValue
                ? LibrarySyncOrigin.merged.rawValue
                : LibrarySyncOrigin.tmdb.rawValue
            if collection == .favorites, !item.favoritePending { item.isFavorite = true }
            if collection == .watchlist, !item.watchlistPending { item.isWatchlisted = true }
        }

        let all = try context.fetch(FetchDescriptor<LibraryItem>())
        for item in all where item.mediaTypeRaw == mediaType.rawValue {
            let locallyEnabled = collection == .favorites ? item.isFavorite : item.isWatchlisted
            let pending = collection == .favorites ? item.favoritePending : item.watchlistPending
            if locallyEnabled, !remoteKeys.contains(item.libraryKey), !pending {
                context.insert(LibraryOutboxItem(
                    title: snapshot(item).title,
                    collection: collection,
                    enabled: true,
                    accountID: accountID,
                    now: now()
                ))
                if collection == .favorites { item.favoritePending = true } else { item.watchlistPending = true }
            } else if !pending, !remoteKeys.contains(item.libraryKey) {
                if collection == .favorites { item.isFavorite = false } else { item.isWatchlisted = false }
            }
            item.accountID = accountID
        }
        try context.save()
    }

    public func pendingMutations(limit: Int) throws -> [LibraryPendingMutation] {
        let values = try context.fetch(FetchDescriptor<LibraryOutboxItem>(sortBy: [SortDescriptor(\.createdAt)]))
        return values.prefix(max(0, limit)).compactMap { value in
            guard let type = MediaType(rawValue: value.mediaTypeRaw),
                  let collection = LibraryCollection(rawValue: value.collectionRaw) else { return nil }
            return LibraryPendingMutation(
                id: value.mutationID,
                libraryKey: value.libraryKey,
                mediaType: type,
                mediaID: value.mediaID,
                collection: collection,
                enabled: value.enabled,
                accountID: value.accountID,
                attemptCount: value.attemptCount
            )
        }
    }

    public func confirmMutation(_ id: UUID) throws {
        let descriptor = FetchDescriptor<LibraryOutboxItem>(predicate: #Predicate { $0.mutationID == id })
        guard let mutation = try context.fetch(descriptor).first else { return }
        let key = mutation.libraryKey
        let collection = LibraryCollection(rawValue: mutation.collectionRaw)
        context.delete(mutation)
        let remaining = try context.fetch(FetchDescriptor<LibraryOutboxItem>(predicate: #Predicate { $0.libraryKey == key }))
        if !remaining.contains(where: { $0.collectionRaw == collection?.rawValue }) {
            for item in try items(forKey: key) {
                if collection == .favorites { item.favoritePending = false }
                if collection == .watchlist { item.watchlistPending = false }
                item.remoteRevision = id.uuidString.lowercased()
                item.syncOriginRaw = LibrarySyncOrigin.tmdb.rawValue
            }
        }
        try context.save()
    }

    public func failMutation(_ id: UUID, message: String) throws {
        let descriptor = FetchDescriptor<LibraryOutboxItem>(predicate: #Predicate { $0.mutationID == id })
        guard let mutation = try context.fetch(descriptor).first else { return }
        mutation.attemptCount += 1
        mutation.lastAttemptAt = now()
        mutation.lastError = String(message.prefix(500))
        try context.save()
    }
}
