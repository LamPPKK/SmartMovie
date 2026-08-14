import SwiftUI

public struct LibraryView: View {
    @Environment(AppContainer.self) private var container
    @State private var model: LibraryViewModel?

    public init() {}

    public var body: some View {
        Group {
            if let model { content(model) } else { ProgressView() }
        }
        .navigationTitle(String(localized: "Library", bundle: .module))
        .cinemaScreen()
        .task {
            if model == nil { model = LibraryViewModel(library: container.library) }
            model?.reload()
        }
    }

    private func content(_ model: LibraryViewModel) -> some View {
        @Bindable var model = model
        return VStack(spacing: 12) {
            Picker(String(localized: "Collection", bundle: .module), selection: $model.collection) {
                ForEach(LibraryCollection.allCases) { item in Text(item.displayName).tag(item) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 440)
            .padding(.horizontal)

            HStack {
                Picker(String(localized: "Content type", bundle: .module), selection: $model.mediaType) {
                    Text(String(localized: "All", bundle: .module)).tag(MediaType?.none)
                    ForEach(MediaType.allCases) { type in Text(type.displayName).tag(MediaType?.some(type)) }
                }
                Picker(String(localized: "Sort by", bundle: .module), selection: $model.sort) {
                    ForEach(LibrarySort.allCases) { sort in Text(sort.displayName).tag(sort) }
                }
            }
            .padding(.horizontal)

            if let error = model.errorMessage {
                StateMessageView(icon: "exclamationmark.triangle", title: String(localized: "Library unavailable", bundle: .module), message: error)
            } else if model.items.isEmpty {
                StateMessageView(
                    icon: model.collection == .favorites ? "heart" : "bookmark",
                    title: model.collection == .favorites
                        ? String(localized: "No favorites yet", bundle: .module)
                        : String(localized: "Your watchlist is empty", bundle: .module),
                    message: String(localized: "Add titles from any detail screen.", bundle: .module)
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(model.items) { item in
                            NavigationLink(value: item.title) { TitleRow(title: item.title) }
                                .catalogNavigationButtonStyle()
                        }
                    }
                    .padding()
                }
            }
        }
        .onChange(of: model.collection) { model.reload() }
        .onChange(of: model.mediaType) { model.reload() }
        .onChange(of: model.sort) { model.reload() }
        .onAppear { model.reload() }
    }
}
