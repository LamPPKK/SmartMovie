import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
public final class AccountListDetailModel {
    public private(set) var list: UserList
    public private(set) var isLoading = false
    public private(set) var isLoadingMore = false
    public private(set) var page = 0
    public private(set) var totalPages = 1
    public private(set) var searchResults: [TitleSummary] = []
    public private(set) var isSearching = false
    public private(set) var errorMessage: String?

    public var name: String
    public var listDescription: String
    public var isPublic: Bool
    public var searchQuery = ""
    private var loadRequestID: UUID?
    private var searchRequestID: UUID?

    public init(list: UserList) {
        self.list = list
        name = list.name
        listDescription = list.description
        isPublic = list.public
        page = list.page ?? 0
        totalPages = list.totalPages ?? 1
    }

    public var canLoadMore: Bool { page > 0 && page < totalPages && !isLoadingMore }
    public var isPendingCreation: Bool { list.id < 0 }

    public func load(
        language: String,
        includeAdult: Bool,
        pending: @escaping () async -> [AccountPendingMutation],
        repository: any AccountListLoading
    ) async {
        applyAdultVisibility(includeAdult: includeAdult)
        guard !isPendingCreation else { return }
        searchRequestID = nil
        isSearching = false
        searchResults = []
        let requestID = UUID()
        loadRequestID = requestID
        isLoading = true
        errorMessage = nil
        defer {
            if loadRequestID == requestID { isLoading = false }
        }
        await loadPage(
            1,
            request: PageRequest(
                language: language,
                includeAdult: includeAdult,
                pending: pending,
                id: requestID
            ),
            repository: repository
        )
    }

    public func loadMore(
        language: String,
        includeAdult: Bool,
        pending: @escaping () async -> [AccountPendingMutation],
        repository: any AccountListLoading
    ) async {
        guard canLoadMore else { return }
        let requestID = UUID()
        loadRequestID = requestID
        isLoadingMore = true
        errorMessage = nil
        defer {
            if loadRequestID == requestID { isLoadingMore = false }
        }
        await loadPage(
            page + 1,
            request: PageRequest(
                language: language,
                includeAdult: includeAdult,
                pending: pending,
                id: requestID
            ),
            repository: repository
        )
    }

    public func search(
        language: String,
        includeAdult: Bool,
        repository: any TitleSearching
    ) async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        let requestID = UUID()
        searchRequestID = requestID
        isSearching = true
        errorMessage = nil
        defer {
            if searchRequestID == requestID { isSearching = false }
        }
        do {
            let result = try await repository.search(query: query, scope: .all, page: 1, language: language)
            try Task.checkCancellation()
            guard searchRequestID == requestID,
                  searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
            let existing = Set(list.results.map(\.libraryKey))
            searchResults = result.results.filter { title in
                (includeAdult || !title.isAdult) && !existing.contains(title.libraryKey)
            }.deduplicatedByLibraryKey()
        } catch is CancellationError {
            return
        } catch {
            if searchRequestID == requestID { errorMessage = error.localizedDescription }
        }
    }

    public func applyAdultVisibility(includeAdult: Bool) {
        guard !includeAdult else { return }
        loadRequestID = nil
        searchRequestID = nil
        isLoadingMore = false
        isSearching = false
        list = replacingResults(list.results.filter { !$0.isAdult })
        searchResults.removeAll(where: \.isAdult)
    }

    public func applyMetadata() {
        list = UserList(
            id: list.id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: listDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            isPublic: isPublic,
            page: list.page,
            totalPages: list.totalPages,
            results: list.results
        )
    }

    public func add(_ title: TitleSummary) {
        list = replacingResults((list.results + [title]).deduplicatedByLibraryKey())
        searchResults.removeAll { $0.libraryKey == title.libraryKey }
    }

    public func remove(_ title: TitleSummary) {
        list = replacingResults(list.results.filter { $0.libraryKey != title.libraryKey })
    }

    public func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    public func clearError() {
        errorMessage = nil
    }

    private func loadPage(
        _ requestedPage: Int,
        request: PageRequest,
        repository: any AccountListLoading
    ) async {
        do {
            let response = try await repository.list(id: list.id, page: requestedPage, language: request.language)
            try Task.checkCancellation()
            let visible = response.results.filter { request.includeAdult || !$0.isAdult }
            let results = requestedPage == 1
                ? visible.deduplicatedByLibraryKey()
                : (list.results + visible).deduplicatedByLibraryKey()
            let currentPending = await request.pending()
            try Task.checkCancellation()
            guard loadRequestID == request.id else { return }
            let remote = UserList(
                id: response.id,
                name: response.name,
                description: response.description,
                isPublic: response.public,
                page: response.page,
                totalPages: response.totalPages,
                results: results
            )
            guard let merged = applyPendingListDetail(
                remote,
                pending: currentPending,
                includeAdult: request.includeAdult
            ) else { return }
            list = merged
            name = merged.name
            listDescription = merged.description
            isPublic = merged.public
            page = merged.page ?? requestedPage
            totalPages = merged.totalPages ?? page
        } catch is CancellationError {
            return
        } catch {
            if loadRequestID == request.id { errorMessage = error.localizedDescription }
        }
    }

    private struct PageRequest {
        let language: String
        let includeAdult: Bool
        let pending: () async -> [AccountPendingMutation]
        let id: UUID
    }

    private func replacingResults(_ results: [TitleSummary]) -> UserList {
        UserList(
            id: list.id,
            name: list.name,
            description: list.description,
            isPublic: list.public,
            page: list.page,
            totalPages: list.totalPages,
            results: results
        )
    }
}

public struct AccountListDetailView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.locale) private var locale
    @State private var model: AccountListDetailModel

    public init(list: UserList) {
        _model = State(initialValue: AccountListDetailModel(list: list))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                metadataCard
                titlesCard
                addTitlesCard
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(24)
        }
        .navigationTitle(model.list.name)
        .cinemaScreen()
        .task(id: taskID) {
            await model.load(
                language: language,
                includeAdult: includeAdult,
                pending: { await container.pendingAccountMutations() },
                repository: container.account
            )
        }
        .alert(String(localized: "Custom list", bundle: .module), isPresented: errorBinding) {
            Button(String(localized: "OK", bundle: .module), role: .cancel) { model.clearError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(String(localized: "List details", bundle: .module))
            if model.isPendingCreation {
                Label(
                    String(localized: "Waiting for this list to sync before editing.", bundle: .module),
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .foregroundStyle(CinemaTheme.muted)
            }
            TextField(String(localized: "List name", bundle: .module), text: $model.name)
                .textFieldStyle(.roundedBorder)
            TextField(String(localized: "Description", bundle: .module), text: $model.listDescription, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...5)
            Toggle(String(localized: "Public list", bundle: .module), isOn: $model.isPublic)
            Button {
                Task { await saveMetadata() }
            } label: {
                Label(String(localized: "Save changes", bundle: .module), systemImage: "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(CinemaTheme.accent)
            .disabled(model.isPendingCreation || model.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(20)
        .background(CinemaTheme.surface, in: RoundedRectangle(cornerRadius: CinemaTheme.cornerRadius))
    }

    private var titlesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(String(localized: "Titles in this list", bundle: .module))
            if model.isLoading && model.list.results.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 100)
            } else if model.list.results.isEmpty {
                Text(String(localized: "This list has no titles yet.", bundle: .module))
                    .foregroundStyle(CinemaTheme.muted)
            } else {
                ForEach(model.list.results) { title in
                    HStack(spacing: 12) {
                        NavigationLink(value: title) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(title.title).font(.headline)
                                Text(title.mediaType.displayName).font(.caption).foregroundStyle(CinemaTheme.muted)
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button(role: .destructive) {
                            Task { await remove(title) }
                        } label: {
                            Label(String(localized: "Remove", bundle: .module), systemImage: "minus.circle")
                        }
                        .disabled(model.isPendingCreation)
                    }
                    Divider().overlay(CinemaTheme.muted.opacity(0.25))
                }
            }
            if model.canLoadMore || model.isLoadingMore {
                Button {
                    Task {
                        await model.loadMore(
                            language: language,
                            includeAdult: includeAdult,
                            pending: { await container.pendingAccountMutations() },
                            repository: container.account
                        )
                    }
                } label: {
                    if model.isLoadingMore { ProgressView() } else { Text(String(localized: "Load more", bundle: .module)) }
                }
                .disabled(model.isLoadingMore)
            }
        }
        .padding(20)
        .background(CinemaTheme.surface, in: RoundedRectangle(cornerRadius: CinemaTheme.cornerRadius))
    }

    private var addTitlesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(String(localized: "Add movies and TV series", bundle: .module))
            HStack {
                TextField(String(localized: "Search titles", bundle: .module), text: $model.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await search() } }
                Button(String(localized: "Search", bundle: .module)) { Task { await search() } }
                    .disabled(model.isSearching || model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if model.isSearching {
                ProgressView()
            }
            ForEach(model.searchResults) { title in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title.title).font(.headline)
                        Text(title.mediaType.displayName).font(.caption).foregroundStyle(CinemaTheme.muted)
                    }
                    Spacer()
                    Button {
                        Task { await add(title) }
                    } label: {
                        Label(String(localized: "Add", bundle: .module), systemImage: "plus.circle")
                    }
                    .disabled(model.isPendingCreation)
                }
            }
        }
        .padding(20)
        .background(CinemaTheme.surface, in: RoundedRectangle(cornerRadius: CinemaTheme.cornerRadius))
    }

    private var language: String { LocaleResolver.tmdbLanguage(for: locale) }
    private var includeAdult: Bool { container.adultContent.isEnabled && container.adultContent.isUnlocked }
    private var taskID: String { "\(model.list.id):\(language):\(includeAdult)" }
    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.clearError() } })
    }

    private func search() async {
        await model.search(language: language, includeAdult: includeAdult, repository: container.catalog)
    }

    private func saveMetadata() async {
        do {
            _ = try await container.queueUpdateList(
                id: model.list.id,
                name: String(model.name.prefix(100)),
                description: String(model.listDescription.prefix(1_000)),
                isPublic: model.isPublic
            )
            model.applyMetadata()
            _ = await container.flushAccountOutbox()
        } catch {
            model.report(error)
        }
    }

    private func add(_ title: TitleSummary) async {
        do {
            _ = try await container.queueListItems(
                id: model.list.id,
                items: [UserListItemMutation(mediaType: title.mediaType, mediaId: title.id)],
                titles: [title],
                remove: false
            )
            if includeAdult || !title.isAdult { model.add(title) }
            _ = await container.flushAccountOutbox()
        } catch {
            model.report(error)
        }
    }

    private func remove(_ title: TitleSummary) async {
        do {
            _ = try await container.queueListItems(
                id: model.list.id,
                items: [UserListItemMutation(mediaType: title.mediaType, mediaId: title.id)],
                titles: [title],
                remove: true
            )
            model.remove(title)
            _ = await container.flushAccountOutbox()
        } catch {
            model.report(error)
        }
    }
}

private extension Array where Element == TitleSummary {
    func deduplicatedByLibraryKey() -> [TitleSummary] {
        var keys = Set<String>()
        return filter { keys.insert($0.libraryKey).inserted }
    }
}
