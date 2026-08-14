import SmartMovieKit
import SwiftData
import SwiftUI

@main
struct SmartMovieNativeApp: App {
    @State private var runtime = AppRuntime()
    @State private var selection: AppTab = .home

    var body: some Scene {
        WindowGroup {
            SmartMovieRootView(selection: $selection)
                .environment(runtime.container)
                .modelContainer(runtime.modelContainer)
                .frame(minWidth: 920, minHeight: 640)
        }
        .commands {
            CommandGroup(after: .sidebar) {
                Button(AppTab.search.title) { selection = .search }
                    .keyboardShortcut("f", modifiers: [.command])
                Button(AppTab.library.title) { selection = .library }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }

        WindowGroup("Title", for: TitleSummary.self) { $title in
            if let title {
                NavigationStack { DetailView(summary: title) }
                    .environment(runtime.container)
                    .modelContainer(runtime.modelContainer)
                    .frame(minWidth: 760, minHeight: 620)
            }
        }
    }
}
