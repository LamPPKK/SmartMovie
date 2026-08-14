import SwiftUI

public struct ExploreView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.locale) private var locale
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var model: ExploreViewModel?
    @State private var showsFilters = false

    public init() {}

    public var body: some View {
        Group {
            if let model { content(model) } else { ProgressView() }
        }
        .navigationTitle(String(localized: "Explore", bundle: .module))
        .toolbar {
            ToolbarItemGroup {
                Button { showsFilters = true } label: {
                    Label(String(localized: "Filters", bundle: .module), systemImage: "line.3.horizontal.decrease.circle")
                }
                #if !os(tvOS)
                if let model {
                    Button { model.layout = model.layout == .grid ? .list : .grid } label: {
                        Label(
                            model.layout == .grid ? String(localized: "List", bundle: .module) : String(localized: "Grid", bundle: .module),
                            systemImage: model.layout == .grid ? "list.bullet" : "square.grid.2x2"
                        )
                    }
                }
                #endif
            }
        }
        .sheet(isPresented: $showsFilters) {
            if let model { FilterSheet(model: model, language: LocaleResolver.tmdbLanguage(for: locale)) }
        }
        .cinemaScreen()
        .task {
            if model == nil { model = ExploreViewModel(catalog: container.catalog) }
            if model?.items.isEmpty == true { model?.reload(language: LocaleResolver.tmdbLanguage(for: locale)) }
        }
    }

    @ViewBuilder
    private func content(_ model: ExploreViewModel) -> some View {
        @Bindable var model = model
        VStack(spacing: 12) {
            MediaPicker(selection: $model.mediaType)
                .frame(maxWidth: 420)
                .padding(.horizontal)
                .onChange(of: model.mediaType) {
                    model.filter = DiscoverFilter()
                    model.reload(language: LocaleResolver.tmdbLanguage(for: locale))
                }
            if model.items.isEmpty, model.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.items.isEmpty, let message = model.errorMessage {
                StateMessageView(
                    icon: "safari",
                    title: String(localized: "Explore is unavailable", bundle: .module),
                    message: message,
                    retry: { model.reload(language: LocaleResolver.tmdbLanguage(for: locale)) }
                )
            } else {
                catalog(model)
            }
        }
    }

    @ViewBuilder
    private func catalog(_ model: ExploreViewModel) -> some View {
        #if os(tvOS)
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 28)], spacing: 36) {
                itemLinks(model, width: 220)
            }
            .padding(40)
        }
        #else
        if model.layout == .grid {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: horizontalSizeClass == .regular ? 180 : 145), spacing: 18)],
                    spacing: 28
                ) {
                    itemLinks(model, width: horizontalSizeClass == .regular ? 180 : 150)
                }
                .padding()
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(model.items) { title in
                        NavigationLink(value: title) { TitleRow(title: title) }
                            .catalogNavigationButtonStyle()
                            .onAppear { model.loadMoreIfNeeded(current: title, language: LocaleResolver.tmdbLanguage(for: locale)) }
                    }
                    if model.isLoading { ProgressView().padding() }
                }
                .padding()
            }
        }
        #endif
    }

    @ViewBuilder
    private func itemLinks(_ model: ExploreViewModel, width: CGFloat) -> some View {
        ForEach(model.items) { title in
            NavigationLink(value: title) { PosterCard(title: title, width: width) }
                .catalogNavigationButtonStyle()
                .onAppear { model.loadMoreIfNeeded(current: title, language: LocaleResolver.tmdbLanguage(for: locale)) }
        }
    }
}

private struct FilterSheet: View {
    @Bindable var model: ExploreViewModel
    let language: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Genres", bundle: .module)) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(model.genres) { genre in
                                Button {
                                    if model.filter.genres.contains(genre.id) {
                                        model.filter.genres.remove(genre.id)
                                    } else {
                                        model.filter.genres.insert(genre.id)
                                    }
                                } label: {
                                    Text(genre.name)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            model.filter.genres.contains(genre.id) ? CinemaTheme.accent : CinemaTheme.surface,
                                            in: Capsule()
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Section(String(localized: "Minimum rating", bundle: .module)) {
                    #if os(tvOS)
                    Picker(String(localized: "Minimum rating", bundle: .module), selection: $model.filter.minimumRating) {
                        ForEach(Array(stride(from: 0.0, through: 9.0, by: 0.5)), id: \.self) { rating in
                            Text(String(format: "%.1f+", rating)).tag(rating)
                        }
                    }
                    #else
                    Slider(value: $model.filter.minimumRating, in: 0 ... 9, step: 0.5)
                    Text(String(format: "%.1f+", model.filter.minimumRating))
                    #endif
                }
                Section(String(localized: "Release year", bundle: .module)) {
                    Picker(String(localized: "Year", bundle: .module), selection: $model.filter.year) {
                        Text(String(localized: "Any year", bundle: .module)).tag(Int?.none)
                        ForEach((1950 ... Calendar.current.component(.year, from: .now)).reversed(), id: \.self) { year in
                            Text(String(year)).tag(Int?.some(year))
                        }
                    }
                }
                Section(String(localized: "Sort by", bundle: .module)) {
                    Picker(String(localized: "Sort by", bundle: .module), selection: $model.filter.sort) {
                        ForEach(DiscoverSort.allCases) { sort in Text(sort.displayName).tag(sort) }
                    }
                }
            }
            .navigationTitle(String(localized: "Filters", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Reset", bundle: .module)) { model.filter = DiscoverFilter() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Apply", bundle: .module)) {
                        model.reload(language: language)
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(CinemaTheme.accent)
    }
}
