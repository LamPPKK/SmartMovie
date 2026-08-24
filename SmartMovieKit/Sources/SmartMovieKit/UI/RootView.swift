import SwiftUI

public enum AppTab: String, CaseIterable, Identifiable {
    case home
    case explore
    case search
    case library
    case profile

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .home: String(localized: "Home", bundle: .module)
        case .explore: String(localized: "Explore", bundle: .module)
        case .search: String(localized: "Search", bundle: .module)
        case .library: String(localized: "Library", bundle: .module)
        case .profile: String(localized: "Profile", bundle: .module)
        }
    }

    public var systemImage: String {
        switch self {
        case .home: "sparkles.rectangle.stack"
        case .explore: "safari"
        case .search: "magnifyingglass"
        case .library: "bookmark.square"
        case .profile: "person.crop.circle"
        }
    }
}

public struct SmartMovieRootView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var localSelection: AppTab = .home
    private let externalSelection: Binding<AppTab>?

    public init() {
        externalSelection = nil
    }

    public init(selection: Binding<AppTab>) {
        externalSelection = selection
    }

    private var selection: Binding<AppTab> {
        externalSelection ?? $localSelection
    }

    public var body: some View {
        platformNavigation
            .task { await container.prepare() }
            .onOpenURL { url in
                Task { await container.accountSession.handleCallback(url) }
            }
            .sheet(item: remotePresentation) { presentation in
                NavigationStack {
                    DetailView(
                        summary: presentation.title,
                        autoplayTrailer: presentation.playsTrailer
                    )
                }
                .environment(container)
            }
            .cinemaScreen()
    }

    private var remotePresentation: Binding<WatchRemotePresentation?> {
        Binding(
            get: { container.watchRemoteCoordinator.presentation },
            set: { value in
                if value == nil {
                    container.watchRemoteCoordinator.dismissPresentation()
                }
            }
        )
    }

    @ViewBuilder
    private var platformNavigation: some View {
        #if os(macOS) || os(visionOS)
        sidebarNavigation
        #elseif os(tvOS)
        tabNavigation
        #else
        if horizontalSizeClass == .regular {
            sidebarNavigation
        } else {
            tabNavigation
        }
        #endif
    }

    private var sidebarNavigation: some View {
        NavigationSplitView {
            List(AppTab.allCases) { tab in
                Button {
                    selection.wrappedValue = tab
                } label: {
                    Label(tab.title, systemImage: tab.systemImage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    selection.wrappedValue == tab ? CinemaTheme.accent.opacity(0.22) : Color.clear
                )
            }
            .navigationTitle("SmartMovie")
        } detail: {
            tabContent(selection.wrappedValue)
        }
    }

    private var tabNavigation: some View {
        TabView(selection: selection) {
            ForEach(AppTab.allCases) { tab in
                tabContent(tab)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
            }
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: AppTab) -> some View {
        switch tab {
        case .home: CatalogNavigationRoot { HomeView() }
        case .explore: CatalogNavigationRoot { ExploreView() }
        case .search: CatalogNavigationRoot { SearchView() }
        case .library: CatalogNavigationRoot { LibraryView() }
        case .profile: CatalogNavigationRoot { ProfileView() }
        }
    }
}

private struct CatalogNavigationRoot<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        NavigationStack {
            content()
                .navigationDestination(for: TitleSummary.self) { title in
                    DetailView(summary: title)
                }
                .navigationDestination(for: CatalogEntity.self) { entity in
                    if case .title(let title) = entity {
                        DetailView(summary: title)
                    } else {
                        EntityDetailView(entity: entity)
                    }
                }
                .navigationDestination(for: SeasonRoute.self) { route in
                    SeasonDetailView(route: route)
                }
                .navigationDestination(for: EpisodeRoute.self) { route in
                    EpisodeDetailView(route: route)
                }
        }
    }
}
