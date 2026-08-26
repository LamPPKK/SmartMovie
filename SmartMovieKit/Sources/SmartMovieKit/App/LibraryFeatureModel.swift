import Observation

@MainActor
@Observable
public final class LibraryViewModel {
    public var collection: LibraryCollection = .favorites
    public var mediaType: MediaType?
    public var sort: LibrarySort = .recentlyAdded
    public private(set) var items: [LibrarySnapshot] = []
    public private(set) var errorMessage: String?
    private let library: any LibraryRepository

    public init(library: any LibraryRepository) {
        self.library = library
    }

    public func reload() {
        do {
            items = try library.items(in: collection, mediaType: mediaType, sort: sort)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
