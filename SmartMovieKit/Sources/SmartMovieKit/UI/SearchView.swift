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
            Picker(String(localized: "Search scope", bundle: .module), selection: $model.entityScope) {
                ForEach(SearchScopeV2.allCases) { scope in Text(scope.displayName).tag(scope) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 520, alignment: .leading)
            .padding(.horizontal)
            .onChange(of: model.entityScope) { schedule(model) }

            if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                StateMessageView(
                    icon: "magnifyingglass",
                    title: String(localized: "Find your next story", bundle: .module),
                    message: String(localized: "Search titles, people, collections, companies, and keywords.", bundle: .module)
                )
            } else if model.entities.isEmpty, model.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.entities.isEmpty, let message = model.errorMessage {
                StateMessageView(
                    icon: "wifi.exclamationmark",
                    title: String(localized: "Search failed", bundle: .module),
                    message: message,
                    retry: { schedule(model) }
                )
            } else if model.entities.isEmpty {
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
                        ForEach(model.entities) { entity in
                            NavigationLink(value: entity) {
                                CatalogEntityCard(entity: entity, width: horizontalSizeClass == .regular ? 180 : 150)
                            }
                            .catalogNavigationButtonStyle()
                            .onAppear {
                                model.loadMoreIfNeeded(
                                    current: entity,
                                    language: LocaleResolver.tmdbLanguage(for: locale),
                                    region: container.regionSettings.effectiveRegion,
                                    includeAdult: container.adultContent.includeAdult
                                )
                            }
                        }
                    }
                    .padding()
                    if model.isLoading { ProgressView().padding() }
                }
            }
        }
        .searchable(text: $model.query, prompt: String(localized: "Titles, people, and collections", bundle: .module))
        .onChange(of: model.query) { schedule(model) }
        .catalogSearchInputBehavior()
    }

    private func schedule(_ model: SearchViewModel) {
        model.scheduleSearch(
            language: LocaleResolver.tmdbLanguage(for: locale),
            region: container.regionSettings.effectiveRegion,
            includeAdult: container.adultContent.includeAdult
        )
    }
}
