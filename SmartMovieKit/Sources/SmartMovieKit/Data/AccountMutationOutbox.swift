import Foundation

public enum AccountMutationPayload: Codable, Hashable, Sendable {
    case titleRating(mediaType: MediaType, mediaID: Int, value: Double?)
    case episodeRating(seriesID: Int, seasonNumber: Int, episodeNumber: Int, value: Double?)
    case createList(name: String, description: String, isPublic: Bool, region: String, language: String)
    case updateList(listID: Int, name: String, description: String, isPublic: Bool)
    case deleteList(listID: Int)
    case mutateListItems(
        listID: Int,
        items: [UserListItemMutation],
        titles: [TitleSummary]?,
        remove: Bool
    )
}

public struct AccountPendingMutation: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let accountID: Int
    public let payload: AccountMutationPayload
    public let createdAt: Date
    public private(set) var attemptCount: Int
    public private(set) var lastAttemptAt: Date?
    public private(set) var lastError: String?

    public init(
        id: UUID = UUID(),
        accountID: Int,
        payload: AccountMutationPayload,
        createdAt: Date = .now,
        attemptCount: Int = 0,
        lastAttemptAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.accountID = accountID
        self.payload = payload
        self.createdAt = createdAt
        self.attemptCount = attemptCount
        self.lastAttemptAt = lastAttemptAt
        self.lastError = lastError
    }

    public var localListID: Int? {
        guard case .createList = payload else { return nil }
        let prefix = id.uuidString.replacingOccurrences(of: "-", with: "").prefix(8)
        let value = Int(prefix, radix: 16).map { $0 & 0x3fff_ffff } ?? 1
        return -max(1, value)
    }

    fileprivate mutating func recordFailure(_ message: String, at date: Date) {
        attemptCount += 1
        lastAttemptAt = date
        lastError = String(message.prefix(500))
    }
}

public protocol AccountMutationStoring: Sendable {
    func enqueue(_ mutation: AccountPendingMutation) async throws
    func pending(accountID: Int, limit: Int) async throws -> [AccountPendingMutation]
    func confirm(_ id: UUID) async throws
    func fail(_ id: UUID, message: String, at date: Date) async throws
    func cancel(_ id: UUID) async throws
    func clear(accountID: Int) async throws
}

/// A local-only durable store. Account mutations are intentionally kept out of
/// SwiftData/CloudKit so pending TMDb writes never roam to another device.
public actor FileAccountMutationStore: AccountMutationStoring {
    private let fileURL: URL
    private var mutations: [AccountPendingMutation]

    public init(fileURL: URL = FileAccountMutationStore.defaultFileURL()) {
        self.fileURL = fileURL
        mutations = Self.loadRecoveringCorruption(from: fileURL)
    }

    public func enqueue(_ mutation: AccountPendingMutation) throws {
        guard !mutations.contains(where: { $0.id == mutation.id }) else { return }
        mutations.append(mutation)
        try persist()
    }

    public func pending(accountID: Int, limit: Int) -> [AccountPendingMutation] {
        mutations
            .filter { $0.accountID == accountID }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt { return lhs.id.uuidString < rhs.id.uuidString }
                return lhs.createdAt < rhs.createdAt
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    public func confirm(_ id: UUID) throws {
        mutations.removeAll { $0.id == id }
        try persist()
    }

    public func fail(_ id: UUID, message: String, at date: Date) throws {
        guard let index = mutations.firstIndex(where: { $0.id == id }) else { return }
        mutations[index].recordFailure(message, at: date)
        try persist()
    }

    public func cancel(_ id: UUID) throws {
        try confirm(id)
    }

    public func clear(accountID: Int) throws {
        mutations.removeAll { $0.accountID == accountID }
        try persist()
    }

    public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("SmartMovie", isDirectory: true)
            .appendingPathComponent("account-mutation-outbox.json", isDirectory: false)
    }

    private func persist() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(mutations).write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    private static func loadRecoveringCorruption(from fileURL: URL) -> [AccountPendingMutation] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([AccountPendingMutation].self, from: data)
        } catch {
            let suffix = String(Int(Date().timeIntervalSince1970))
            let recoveryURL = fileURL.appendingPathExtension("corrupt-\(suffix)")
            try? FileManager.default.copyItem(at: fileURL, to: recoveryURL)
            return []
        }
    }
}

public struct AccountMutationFlushReport: Sendable {
    public let delivered: [UUID: MutationResult]
    public let failure: String?

    public init(delivered: [UUID: MutationResult] = [:], failure: String? = nil) {
        self.delivered = delivered
        self.failure = failure
    }
}

public struct AccountMutationReceipt: Sendable {
    public let id: UUID
    public let delivered: Bool
    public let result: MutationResult?
}

public struct PendingRating: Sendable {
    public let value: Double?
}

public actor AccountMutationCoordinator {
    private let account: any AccountRepository
    private let store: any AccountMutationStoring
    private let now: @Sendable () -> Date
    private var isFlushing = false

    public init(
        account: any AccountRepository,
        store: any AccountMutationStoring = FileAccountMutationStore(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.account = account
        self.store = store
        self.now = now
    }

    public func enqueue(
        _ payload: AccountMutationPayload,
        accountID: Int,
        id: UUID = UUID()
    ) async throws -> AccountMutationReceipt {
        let mutation = AccountPendingMutation(id: id, accountID: accountID, payload: payload, createdAt: now())
        try await store.enqueue(mutation)
        return AccountMutationReceipt(id: id, delivered: false, result: nil)
    }

    public func flush(accountID: Int, limit: Int = 100) async -> AccountMutationFlushReport {
        guard !isFlushing else { return AccountMutationFlushReport() }
        isFlushing = true
        defer { isFlushing = false }

        let pending: [AccountPendingMutation]
        do {
            pending = try await store.pending(accountID: accountID, limit: limit)
        } catch {
            return AccountMutationFlushReport(failure: error.localizedDescription)
        }

        var delivered: [UUID: MutationResult] = [:]
        for mutation in pending {
            do {
                let result = try await send(mutation)
                guard result.mutationId == mutation.id else {
                    throw APIError.decoding("The mutation acknowledgement did not match its idempotency key.")
                }
                try await store.confirm(mutation.id)
                delivered[mutation.id] = result
            } catch {
                try? await store.fail(mutation.id, message: error.localizedDescription, at: now())
                return AccountMutationFlushReport(delivered: delivered, failure: error.localizedDescription)
            }
        }
        return AccountMutationFlushReport(delivered: delivered)
    }

    public func pending(accountID: Int, limit: Int = 500) async -> [AccountPendingMutation] {
        (try? await store.pending(accountID: accountID, limit: limit)) ?? []
    }

    public func cancel(_ id: UUID) async throws {
        try await store.cancel(id)
    }

    public func clear(accountID: Int) async throws {
        try await store.clear(accountID: accountID)
    }

    public func pendingTitleRating(accountID: Int, mediaType: MediaType, mediaID: Int) async -> PendingRating? {
        let values = await pending(accountID: accountID)
        for mutation in values.reversed() {
            if case .titleRating(let candidateType, let candidateID, let value) = mutation.payload,
               candidateType == mediaType, candidateID == mediaID {
                return PendingRating(value: value)
            }
        }
        return nil
    }

    public func pendingEpisodeRating(
        accountID: Int,
        seriesID: Int,
        seasonNumber: Int,
        episodeNumber: Int
    ) async -> PendingRating? {
        let values = await pending(accountID: accountID)
        for mutation in values.reversed() {
            if case .episodeRating(let candidateSeries, let candidateSeason, let candidateEpisode, let value) = mutation.payload,
               candidateSeries == seriesID, candidateSeason == seasonNumber, candidateEpisode == episodeNumber {
                return PendingRating(value: value)
            }
        }
        return nil
    }

    private func send(_ mutation: AccountPendingMutation) async throws -> MutationResult {
        switch mutation.payload {
        case .titleRating(let mediaType, let mediaID, let value):
            try await account.setRating(mediaType: mediaType, id: mediaID, value: value, mutationID: mutation.id)
        case .episodeRating(let seriesID, let seasonNumber, let episodeNumber, let value):
            try await account.setEpisodeRating(
                seriesID: seriesID,
                season: seasonNumber,
                episode: episodeNumber,
                value: value,
                mutationID: mutation.id
            )
        case .createList(let name, let description, let isPublic, let region, let language):
            try await account.createList(
                UserListMetadataMutation(
                    name: name,
                    description: description,
                    isPublic: isPublic,
                    region: region,
                    language: language
                ),
                mutationID: mutation.id
            )
        case .updateList(let listID, let name, let description, let isPublic):
            try await account.updateList(
                id: listID,
                name: name,
                description: description,
                isPublic: isPublic,
                mutationID: mutation.id
            )
        case .deleteList(let listID):
            try await account.deleteList(id: listID, mutationID: mutation.id)
        case .mutateListItems(let listID, let items, _, let remove):
            try await account.mutateListItems(id: listID, items: items, remove: remove, mutationID: mutation.id)
        }
    }
}
