#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import SmartMovieKit

final class ArtworkLayoutTests: XCTestCase {
    @MainActor
    func testLoadedBackdropKeepsCompactHeroWithinProposedWidth() throws {
        let image = Image(nsImage: NSImage(size: NSSize(width: 1920, height: 1080)))
        let content = ArtworkContent(phase: .success(image), kind: .backdrop, contentMode: .fill, isLoading: false)
        let renderer = ImageRenderer(content: content.frame(height: 390))
        renderer.proposedSize = ProposedViewSize(width: 343, height: nil)

        let rendered = try XCTUnwrap(renderer.nsImage)
        XCTAssertEqual(rendered.size.width, 343, accuracy: 0.5)
        XCTAssertEqual(rendered.size.height, 390, accuracy: 0.5)
    }

    @MainActor
    func testFitArtworkDoesNotShrinkTheRequestedViewport() throws {
        let image = Image(nsImage: NSImage(size: NSSize(width: 200, height: 800)))
        let content = ArtworkContent(phase: .success(image), kind: .profile, contentMode: .fit, isLoading: false)
        let renderer = ImageRenderer(content: content.frame(height: 180))
        renderer.proposedSize = ProposedViewSize(width: 320, height: nil)

        let rendered = try XCTUnwrap(renderer.nsImage)
        XCTAssertEqual(rendered.size.width, 320, accuracy: 0.5)
        XCTAssertEqual(rendered.size.height, 180, accuracy: 0.5)
    }

    @MainActor
    func testNilURLRendersUnavailableArtworkRatherThanLoadingPlaceholder() throws {
        let actual = ImageRenderer(content: RemoteArtwork(url: nil, kind: .poster).frame(width: 148, height: 222))
        let expected = ImageRenderer(content: ArtworkContent(
            phase: .failure(URLError(.cannotLoadFromNetwork)),
            kind: .poster,
            contentMode: .fill,
            isLoading: false
        ).frame(width: 148, height: 222))
        let actualPixels = try XCTUnwrap(actual.cgImage?.dataProvider?.data)
        let expectedPixels = try XCTUnwrap(expected.cgImage?.dataProvider?.data)

        XCTAssertEqual(actualPixels as Data, expectedPixels as Data)
    }

    @MainActor
    func testMissingAndFailedArtworkUseSameViewportAsLoadedArtwork() throws {
        let phases: [AsyncImagePhase] = [.empty, .failure(URLError(.cannotLoadFromNetwork))]
        for phase in phases {
            let content = ArtworkContent(phase: phase, kind: .poster, contentMode: .fill, isLoading: false)
            let renderer = ImageRenderer(content: content.frame(height: 222))
            renderer.proposedSize = ProposedViewSize(width: 148, height: nil)

            let rendered = try XCTUnwrap(renderer.nsImage)
            XCTAssertEqual(rendered.size.width, 148, accuracy: 0.5)
            XCTAssertEqual(rendered.size.height, 222, accuracy: 0.5)
        }
    }
}
#endif
