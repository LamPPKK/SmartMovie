import Foundation
import SwiftData

@Model
public final class EpisodeWatchRecord {
    public var episodeKey: String = ""
    public var seriesID: Int = 0
    public var seasonNumber: Int = 0
    public var episodeNumber: Int = 0
    public var watchedAt: Date = Date.distantPast
    public var updatedAt: Date = Date.distantPast

    public init(key: EpisodeWatchKey, now: Date = .now) {
        episodeKey = key.rawValue
        seriesID = key.seriesID
        seasonNumber = key.seasonNumber
        episodeNumber = key.episodeNumber
        watchedAt = now
        updatedAt = now
    }
}

@MainActor
public final class SwiftDataEpisodeProgressRepository: EpisodeProgressRepository {
    private let context: ModelContext
    private let now: () -> Date

    public init(context: ModelContext, now: @escaping () -> Date = { .now }) {
        self.context = context
        self.now = now
    }

    public func isWatched(_ key: EpisodeWatchKey) throws -> Bool {
        try !records(for: key.rawValue).isEmpty
    }

    public func watchedEpisodeNumbers(seriesID: Int, seasonNumber: Int) throws -> Set<Int> {
        let descriptor = FetchDescriptor<EpisodeWatchRecord>(predicate: #Predicate {
            $0.seriesID == seriesID && $0.seasonNumber == seasonNumber
        })
        return Set(try context.fetch(descriptor).map(\.episodeNumber))
    }

    public func setWatched(_ watched: Bool, for key: EpisodeWatchKey) throws {
        let matches = try records(for: key.rawValue)
        if watched {
            let timestamp = now()
            let winner = matches.max(by: { $0.updatedAt < $1.updatedAt }) ?? EpisodeWatchRecord(key: key, now: timestamp)
            if winner.modelContext == nil { context.insert(winner) }
            winner.watchedAt = timestamp
            winner.updatedAt = timestamp
            for duplicate in matches where duplicate !== winner { context.delete(duplicate) }
        } else {
            for match in matches { context.delete(match) }
        }
        try context.save()
    }

    public func setSeasonWatched(
        _ watched: Bool,
        seriesID: Int,
        seasonNumber: Int,
        episodeNumbers: [Int]
    ) throws {
        let requested = Set(episodeNumbers.filter { $0 >= 0 })
        guard !requested.isEmpty else { return }
        let descriptor = FetchDescriptor<EpisodeWatchRecord>(predicate: #Predicate {
            $0.seriesID == seriesID && $0.seasonNumber == seasonNumber
        })
        let existing = try context.fetch(descriptor).filter { requested.contains($0.episodeNumber) }
        if watched {
            let existingNumbers = Set(existing.map(\.episodeNumber))
            let timestamp = now()
            for number in requested.subtracting(existingNumbers) {
                context.insert(EpisodeWatchRecord(
                    key: EpisodeWatchKey(seriesID: seriesID, seasonNumber: seasonNumber, episodeNumber: number),
                    now: timestamp
                ))
            }
        } else {
            for record in existing { context.delete(record) }
        }
        try context.save()
        try reconcileDuplicates()
    }

    public func reconcileDuplicates() throws {
        let all = try context.fetch(FetchDescriptor<EpisodeWatchRecord>())
        for duplicates in Dictionary(grouping: all, by: \.episodeKey).values where duplicates.count > 1 {
            guard let winner = duplicates.max(by: { $0.updatedAt < $1.updatedAt }) else { continue }
            for duplicate in duplicates where duplicate !== winner { context.delete(duplicate) }
        }
        try context.save()
    }

    private func records(for key: String) throws -> [EpisodeWatchRecord] {
        let descriptor = FetchDescriptor<EpisodeWatchRecord>(predicate: #Predicate { $0.episodeKey == key })
        return try context.fetch(descriptor)
    }
}
