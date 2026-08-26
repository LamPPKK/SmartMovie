import Foundation
import XCTest
@testable import SmartMovieKit

final class CatalogMediaPresentationTests: XCTestCase {
    func testImagesRemoveBlankAndDuplicatePathsWithoutReordering() {
        let values = [
            image(path: "/first.jpg"),
            image(path: " "),
            image(path: "/first.jpg", kind: "poster"),
            image(path: "/second.jpg", kind: "poster")
        ]

        XCTAssertEqual(CatalogMediaPresentation.images(values).map(\.filePath), ["/first.jpg", "/second.jpg"])
    }

    func testVideosOnlyExposeUniquePlayableYouTubeKeys() {
        let values = [
            video(id: "1", key: "trailer", site: "YouTube"),
            video(id: "2", key: "trailer", site: "youtube"),
            video(id: "3", key: "clip", site: "Vimeo"),
            video(id: "4", key: " ", site: "YouTube")
        ]

        let presented = CatalogMediaPresentation.videos(values)

        XCTAssertEqual(presented.map(\.id), ["1"])
        XCTAssertEqual(CatalogMediaPresentation.videoURL(for: presented[0])?.host, "www.youtube.com")
        XCTAssertNil(CatalogMediaPresentation.videoURL(for: values[2]))
    }

    func testExternalIdentifiersRemoveBlankValuesAndUseStableOrder() {
        let values = CatalogMediaPresentation.externalIdentifiers([
            "tvdb_id": "42",
            "blank": " ",
            "imdb_id": "tt123"
        ])

        XCTAssertEqual(values.map(\.0), ["imdb_id", "tvdb_id"])
        XCTAssertEqual(values.map(\.1), ["tt123", "42"])
    }

    private func image(path: String, kind: String = "backdrop") -> ImageAsset {
        ImageAsset(
            kind: kind,
            filePath: path,
            aspectRatio: 1.78,
            height: 720,
            width: 1280,
            language: nil,
            voteAverage: 0
        )
    }

    private func video(id: String, key: String, site: String) -> Video {
        Video(id: id, key: key, name: "Sample", site: site, type: "Trailer", official: true)
    }
}
