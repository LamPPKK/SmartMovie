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
        VStack(spacing: 10) {
            searchModePicker(model)
            searchOptions(model)
            queryField(model)
            resultsView(model)
        }
        .catalogSearchInputBehavior()
    }

    private func searchModePicker(_ model: SearchViewModel) -> some View {
        Picker(
            String(localized: "Search mode", bundle: .module),
            selection: Binding(get: { model.mode }, set: { model.setMode($0) })
        ) {
            ForEach(CatalogSearchMode.allCases) { mode in Text(mode.displayName).tag(mode) }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 520, alignment: .leading)
        .padding(.horizontal)
    }

    @ViewBuilder
    private func searchOptions(_ model: SearchViewModel) -> some View {
        @Bindable var model = model
        if model.mode == .catalog {
            Picker(String(localized: "Search scope", bundle: .module), selection: $model.entityScope) {
                ForEach(SearchScopeV2.allCases) { scope in Text(scope.displayName).tag(scope) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 520, alignment: .leading)
            .padding(.horizontal)
            .onChange(of: model.entityScope) { schedule(model) }
        } else {
            HStack(spacing: 12) {
                Picker(String(localized: "Source", bundle: .module), selection: $model.externalIDSource) {
                    ForEach(ExternalIDSource.allCases) { source in Text(source.displayName).tag(source) }
                }
                .pickerStyle(.menu)
                .onChange(of: model.externalIDSource) { model.resetExternalIDResults() }

                Button(String(localized: "Find matches", bundle: .module)) {
                    model.findExternalID(language: LocaleResolver.tmdbLanguage(for: locale))
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isLoading)
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(.horizontal)
        }
    }

    private func queryField(_ model: SearchViewModel) -> some View {
        @Bindable var model = model
        return TextField(
            model.mode == .catalog
                ? String(localized: "Titles, people, and collections", bundle: .module)
                : model.externalIDSource.example,
            text: $model.query
        )
        .textFieldStyle(.roundedBorder)
        .autocorrectionDisabled()
        .frame(maxWidth: 520)
        .padding(.horizontal)
        .onSubmit {
            if model.mode == .catalog {
                schedule(model)
            } else {
                model.findExternalID(language: LocaleResolver.tmdbLanguage(for: locale))
            }
        }
        .onChange(of: model.query) {
            if model.mode == .catalog {
                schedule(model)
            } else {
                model.resetExternalIDResults()
            }
        }
    }

    @ViewBuilder
    private func resultsView(_ model: SearchViewModel) -> some View {
        if model.mode == .externalID, !model.hasSubmittedExternalID {
            StateMessageView(
                icon: "number.square",
                title: String(localized: "Search by external ID", bundle: .module),
                message: String(localized: "Enter an ID from another database and choose its source.", bundle: .module)
            )
        } else if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                retry: { retry(model) }
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

    private func retry(_ model: SearchViewModel) {
        if model.mode == .externalID {
            model.findExternalID(language: LocaleResolver.tmdbLanguage(for: locale))
        } else {
            schedule(model)
        }
    }

    private func schedule(_ model: SearchViewModel) {
        model.scheduleSearch(
            language: LocaleResolver.tmdbLanguage(for: locale),
            region: container.regionSettings.effectiveRegion,
            includeAdult: container.adultContent.includeAdult
        )
    }
}
