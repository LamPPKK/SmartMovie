import SmartMovieKit
import SwiftData
import SwiftUI

@main
struct SmartMovieVisionApp: App {
    @State private var runtime = AppRuntime()

    var body: some Scene {
        WindowGroup {
            SmartMovieRootView()
                .environment(runtime.container)
                .modelContainer(runtime.modelContainer)
                .frame(minWidth: 980, minHeight: 680)
        }
        .defaultSize(width: 1_280, height: 820)
        .windowResizability(.contentMinSize)

        WindowGroup("Title", for: TitleSummary.self) { $title in
            if let title {
                NavigationStack {
                    DetailView(summary: title)
                }
                .environment(runtime.container)
                .modelContainer(runtime.modelContainer)
                .frame(minWidth: 760, minHeight: 620)
            }
        }
        .defaultSize(width: 920, height: 760)
        .windowResizability(.contentMinSize)
    }
}
