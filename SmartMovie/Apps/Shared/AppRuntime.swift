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

        let persistentContainer = Self.makeModelContainer()
        modelContainer = persistentContainer

        let baseURL = Bundle.main.object(forInfoDictionaryKey: "CATALOG_BASE_URL") as? String
        let serviceURL = URL(string: baseURL ?? "") ?? URL(string: "http://127.0.0.1:8787")!
        let catalog = RemoteCatalogRepository(client: APIClient(baseURL: serviceURL))
        let library = SwiftDataLibraryRepository(context: ModelContext(persistentContainer))
        container = AppContainer(catalog: catalog, library: library)
    }

    private static func makeModelContainer() -> ModelContainer {
        do {
            return try LibraryStoreFactory.makeContainer(
                cloudKitContainerIdentifier: activeCloudKitContainerIdentifier
            )
        } catch {
            // A local store keeps the app usable when iCloud is unavailable or an
            // unsigned development build does not have CloudKit entitlements yet.
            do {
                return try LibraryStoreFactory.makeContainer(
                    cloudKitContainerIdentifier: nil,
                    inMemory: false
                )
            } catch {
                do {
                    return try LibraryStoreFactory.makeContainer(
                        cloudKitContainerIdentifier: nil,
                        inMemory: true
                    )
                } catch {
                    preconditionFailure("Unable to initialize SmartMovie library storage: \(error)")
                }
            }
        }
    }

    private static var activeCloudKitContainerIdentifier: String? {
        #if targetEnvironment(simulator)
        // Unsigned simulator and CI builds cannot access CloudKit entitlements.
        nil
        #else
        cloudKitContainerIdentifier
        #endif
    }
}
