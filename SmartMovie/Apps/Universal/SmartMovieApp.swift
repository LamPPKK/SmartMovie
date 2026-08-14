import SmartMovieKit
import SwiftData
import SwiftUI

@main
struct SmartMovieApp: App {
    @State private var runtime = AppRuntime()

    var body: some Scene {
        WindowGroup {
            SmartMovieRootView()
                .environment(runtime.container)
                .modelContainer(runtime.modelContainer)
        }
    }
}
