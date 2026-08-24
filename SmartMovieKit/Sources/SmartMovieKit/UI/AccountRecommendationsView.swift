import Observation
import SwiftUI

@MainActor
@Observable
public final class AccountRecommendationsModel {
    public private(set) var mediaType: MediaType = .movie
    public private(set) var state: Loadable<[TitleSummary]> = .idle
    public private(set) var page = 0
    public private(set) var totalPages = 1
    public private(set) var isLoadingMore = false
    public private(set) var paginationError: String?

    public init() {}

    public var canLoadMore: Bool { page > 0 && page < totalPages && !isLoadingMore }

    public func select(_ type: MediaType) {
        guard type != mediaType else { return }
        mediaType = type
        state = .idle
        page = 0
        totalPages = 1
        paginationError = nil
    }

    public func reload(
        language: String,
        includeAdult: Bool,
        repository: any AccountRecommendationsLoading
    ) async {
        let requestedType = mediaType
        state = .loading
        page = 0
        totalPages = 1
        paginationError = nil
        await load(
            page: 1,
            type: requestedType,
            language: language,
            includeAdult: includeAdult,
            repository: repository
        )
    }

    public func loadMore(
        language: String,
        includeAdult: Bool,
        repository: any AccountRecommendationsLoading
    ) async {
        guard canLoadMore else { return }
        isLoadingMore = true
        paginationError = nil
        let requestedType = mediaType
        await load(
            page: page + 1,
            type: requestedType,
            language: language,
            includeAdult: includeAdult,
            repository: repository
        )
        isLoadingMore = false
    }

    private func load(
        page requestedPage: Int,
        type: MediaType,
        language: String,
        includeAdult: Bool,
        repository: any AccountRecommendationsLoading
    ) async {
        do {
            let result = try await repository.recommendations(
                mediaType: type,
                page: requestedPage,
                language: language
            )
            try Task.checkCancellation()
            guard type == mediaType else { return }
            let visible = result.results.filter { includeAdult || !$0.isAdult }
            let existing: [TitleSummary] = if requestedPage == 1 {
                []
            } else if case .loaded(let values) = state {
                values
            } else {
                []
            }
            state = .loaded((existing + visible).deduplicatedByLibraryKey())
            page = result.page
            totalPages = result.totalPages
        } catch is CancellationError {
            return
        } catch {
            if requestedPage == 1 {
                state = .failed(error.localizedDescription)
            } else {
                paginationError = error.localizedDescription
            }
        }
    }
}

struct AccountRecommendationsView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.locale) private var locale
    @State private var model = AccountRecommendationsModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(String(localized: "Account recommendations", bundle: .module))
            Picker(String(localized: "Media type", bundle: .module), selection: mediaTypeBinding) {
                Text(String(localized: "Movies", bundle: .module)).tag(MediaType.movie)
                Text(String(localized: "TV Series", bundle: .module)).tag(MediaType.tv)
            }
            .pickerStyle(.segmented)

            recommendationsContent
        }
        .padding(20)
        .background(CinemaTheme.surface, in: RoundedRectangle(cornerRadius: CinemaTheme.cornerRadius))
        .task(id: taskID) { await reload() }
    }

    @ViewBuilder
    private var recommendationsContent: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 120)
        case .failed(let message):
            StateMessageView(
                icon: "sparkles.tv",
                title: String(localized: "Recommendations unavailable", bundle: .module),
                message: message,
                retry: { Task { await reload() } }
            )
        case .loaded(let titles):
            if titles.isEmpty {
                Text(String(localized: "No account recommendations yet.", bundle: .module))
                    .foregroundStyle(CinemaTheme.muted)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(titles) { title in
                            NavigationLink(value: title) { PosterCard(title: title) }
                                .catalogNavigationButtonStyle()
                        }
                    }
                }
            }
            if model.canLoadMore || model.isLoadingMore {
                Button {
                    Task { await loadMore() }
                } label: {
                    if model.isLoadingMore {
                        ProgressView()
                    } else {
                        Label(String(localized: "Load more", bundle: .module), systemImage: "chevron.down")
                    }
                }
                .disabled(model.isLoadingMore)
            }
            if let paginationError = model.paginationError {
                Text(paginationError).font(.footnote).foregroundStyle(CinemaTheme.accent)
            }
        }
    }

    private var mediaTypeBinding: Binding<MediaType> {
        Binding(get: { model.mediaType }, set: { model.select($0) })
    }

    private var taskID: String {
        "\(model.mediaType.rawValue):\(language):\(includeAdult)"
    }

    private var language: String { LocaleResolver.tmdbLanguage(for: locale) }
    private var includeAdult: Bool { container.adultContent.isEnabled && container.adultContent.isUnlocked }

    private func reload() async {
        await model.reload(language: language, includeAdult: includeAdult, repository: container.account)
    }

    private func loadMore() async {
        await model.loadMore(language: language, includeAdult: includeAdult, repository: container.account)
    }
}

private extension Array where Element == TitleSummary {
    func deduplicatedByLibraryKey() -> [TitleSummary] {
        var keys = Set<String>()
        return filter { keys.insert($0.libraryKey).inserted }
    }
}
