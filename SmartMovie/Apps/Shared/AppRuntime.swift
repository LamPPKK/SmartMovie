import Foundation
import Security
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
        let client = APIClient(baseURL: serviceURL)
        let catalog = RemoteCatalogRepository(client: client)
        let account = RemoteAccountRepository(client: client)
        let library = SwiftDataLibraryRepository(context: ModelContext(persistentContainer))
        let remoteCoordinator = WatchRemoteCoordinator()
        #if os(iOS) && !targetEnvironment(macCatalyst)
        let watchRemoteSession: (any WatchRemoteSession)? = PhoneWatchRemoteController(
            library: library,
            coordinator: remoteCoordinator
        )
        #else
        let watchRemoteSession: (any WatchRemoteSession)? = nil
        #endif
        container = AppContainer(
            catalog: catalog,
            library: library,
            account: account,
            watchRemoteSession: watchRemoteSession,
            watchRemoteCoordinator: remoteCoordinator
        )
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
        // Creating a SwiftData CloudKit store without the matching entitlement can
        // fail asynchronously inside CoreData, after ModelContainer.init returns.
        // Inspect the signed process first so unsigned simulator/CI/local builds use
        // the durable local store instead of crashing during app launch.
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                  task,
                  "com.apple.developer.icloud-container-identifiers" as CFString,
                  nil
              ),
              let identifiers = value as? [String],
              identifiers.contains(cloudKitContainerIdentifier) else {
            return nil
        }
        return cloudKitContainerIdentifier
        #elseif targetEnvironment(simulator)
        return nil
        #else
        // Device, TV and Vision distribution builds are signed against the
        // entitlements declared in project.yml. Simulator smoke tests stay local.
        return cloudKitContainerIdentifier
        #endif
    }
}
