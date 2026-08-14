import SwiftUI

@main
struct SmartMovieWatchApp: App {
    @State private var model = WatchRemoteModel()

    var body: some Scene {
        WindowGroup {
            WatchRemoteView(model: model)
        }
    }
}
