import Foundation

func applyPendingLists(
    _ remote: [UserList],
    pending mutations: [AccountPendingMutation]
) -> [UserList] {
    var merged = remote
    for mutation in mutations.sorted(by: pendingMutationOrder) {
        switch mutation.payload {
        case .createList(let name, let description, let isPublic, _, _):
            guard let localID = mutation.localListID,
                  !merged.contains(where: { $0.id == localID }) else { continue }
            merged.append(UserList(
                id: localID,
                name: name,
                description: description,
                isPublic: isPublic,
                results: []
            ))
        case .updateList(let listID, let name, let description, let isPublic):
            guard let index = merged.firstIndex(where: { $0.id == listID }) else { continue }
            merged[index] = replacing(
                merged[index],
                name: name,
                description: description,
                isPublic: isPublic
            )
        case .deleteList(let listID):
            merged.removeAll { $0.id == listID }
        case .mutateListItems(let listID, let items, let titles, let remove):
            guard let index = merged.firstIndex(where: { $0.id == listID }) else { continue }
            let keys = Set(items.map { "\($0.mediaType.rawValue):\($0.mediaId)" })
            let results: [TitleSummary]
            if remove {
                results = merged[index].results.filter { !keys.contains($0.libraryKey) }
            } else {
                let snapshots = (titles ?? []).filter { keys.contains($0.libraryKey) }
                results = deduplicateTitles(merged[index].results + snapshots)
            }
            merged[index] = replacing(merged[index], results: results)
        case .titleRating, .episodeRating:
            continue
        }
    }
    return merged
}

func applyPendingListDetail(
    _ remote: UserList,
    pending mutations: [AccountPendingMutation],
    includeAdult: Bool = true
) -> UserList? {
    guard let merged = applyPendingLists([remote], pending: mutations).first(where: { $0.id == remote.id }) else {
        return nil
    }
    return includeAdult ? merged : replacing(merged, results: merged.results.filter { !$0.isAdult })
}

func loadAllUserLists(
    maxPages: Int = 500,
    loadPage: @Sendable (Int) async throws -> PagedResult<UserList>
) async throws -> [UserList] {
    var page = 1
    var totalPages = 1
    var lists: [UserList] = []
    repeat {
        let response = try await loadPage(page)
        lists.append(contentsOf: response.results)
        totalPages = min(max(response.totalPages, 1), maxPages)
        page += 1
    } while page <= totalPages
    var seen = Set<Int>()
    return lists.filter { seen.insert($0.id).inserted }
}

private func pendingMutationOrder(_ lhs: AccountPendingMutation, _ rhs: AccountPendingMutation) -> Bool {
    if lhs.createdAt == rhs.createdAt { return lhs.id.uuidString < rhs.id.uuidString }
    return lhs.createdAt < rhs.createdAt
}

private func replacing(
    _ list: UserList,
    name: String? = nil,
    description: String? = nil,
    isPublic: Bool? = nil,
    results: [TitleSummary]? = nil
) -> UserList {
    UserList(
        id: list.id,
        name: name ?? list.name,
        description: description ?? list.description,
        isPublic: isPublic ?? list.public,
        page: list.page,
        totalPages: list.totalPages,
        results: results ?? list.results
    )
}

private func deduplicateTitles(_ titles: [TitleSummary]) -> [TitleSummary] {
    var keys = Set<String>()
    return titles.filter { keys.insert($0.libraryKey).inserted }
}
