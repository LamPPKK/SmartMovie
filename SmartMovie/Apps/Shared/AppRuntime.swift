import Foundation
import SmartMovieKit
import SwiftData

@MainActor
final class AppRuntime {
    static let cloudKitContainerIdentifier = "iCloud.LamNDT.SmartMovie"

    let container: AppContainer
    let modelContainer: ModelContainer

    init() {
        URLCache.shared = URLCache(
            memoryCapacity: 96 * 1_024 * 1_024,
            diskCapacity: 512 * 1_024 * 1_024,
            diskPath: "SmartMovieArtwork"
        )

        let persistentContainer: ModelContainer
        do {
            persistentContainer = try LibraryStoreFactory.makeContainer(
                cloudKitContainerIdentifier: Self.cloudKitContainerIdentifier
            )
        } catch {
            // A local store keeps the app usable when iCloud is unavailable or an
            // unsigned development build does not have CloudKit entitlements yet.
            persistentContainer = try! LibraryStoreFactory.makeContainer(
                cloudKitContainerIdentifier: nil,
                inMemory: false
            )
        }
        modelContainer = persistentContainer

        let baseURL = Bundle.main.object(forInfoDictionaryKey: "CATALOG_BASE_URL") as? String
        let serviceURL = URL(string: baseURL ?? "") ?? URL(string: "http://127.0.0.1:8787")!
        let catalog = RemoteCatalogRepository(client: APIClient(baseURL: serviceURL))
        let library = SwiftDataLibraryRepository(context: ModelContext(persistentContainer))
        container = AppContainer(catalog: catalog, library: library)
    }
}
