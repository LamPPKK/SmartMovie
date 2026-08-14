import SwiftUI

public struct SearchView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.locale) private var locale
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var model: SearchViewModel?

    public init() {}

    public var body: some View {
        Group {
            if let model { content(model) } else { ProgressView() }
        }
        .navigationTitle(String(localized: "Search", bundle: .module))
        .cinemaScreen()
        .task {
            if model == nil { model = SearchViewModel(catalog: container.catalog) }
        }
    }

    private func content(_ model: SearchViewModel) -> some View {
        @Bindable var model = model
        return VStack(spacing: 10) {
            Picker(String(localized: "Search scope", bundle: .module), selection: $model.scope) {
                ForEach(SearchScope.allCases) { scope in Text(scope.displayName).tag(scope) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 460)
            .padding(.horizontal)
            .onChange(of: model.scope) { model.scheduleSearch(language: LocaleResolver.tmdbLanguage(for: locale)) }

            if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                StateMessageView(
                    icon: "magnifyingglass",
                    title: String(localized: "Find your next story", bundle: .module),
                    message: String(localized: "Search movies and TV series by title.", bundle: .module)
                )
            } else if model.items.isEmpty, model.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.items.isEmpty, let message = model.errorMessage {
                StateMessageView(
                    icon: "wifi.exclamationmark",
                    title: String(localized: "Search failed", bundle: .module),
                    message: message,
                    retry: { model.scheduleSearch(language: LocaleResolver.tmdbLanguage(for: locale)) }
                )
            } else if model.items.isEmpty {
                StateMessageView(
                    icon: "film.stack",
                    title: String(localized: "No results", bundle: .module),
                    message: String(localized: "Try another title or content type.", bundle: .module)
                )
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: horizontalSizeClass == .regular ? 180 : 145), spacing: 18)],
                        spacing: 28
                    ) {
                        ForEach(model.items) { title in
                            NavigationLink(value: title) {
                                PosterCard(title: title, width: horizontalSizeClass == .regular ? 180 : 150)
                            }
                            .catalogNavigationButtonStyle()
                            .onAppear { model.loadMoreIfNeeded(current: title, language: LocaleResolver.tmdbLanguage(for: locale)) }
                        }
                    }
                    .padding()
                    if model.isLoading { ProgressView().padding() }
                }
            }
        }
        .searchable(text: $model.query, prompt: String(localized: "Movies and TV series", bundle: .module))
        .onChange(of: model.query) { model.scheduleSearch(language: LocaleResolver.tmdbLanguage(for: locale)) }
        .catalogSearchInputBehavior()
    }
}
