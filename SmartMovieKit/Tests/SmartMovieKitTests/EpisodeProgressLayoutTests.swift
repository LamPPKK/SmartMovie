#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import SmartMovieKit

final class EpisodeProgressLayoutTests: XCTestCase {
    @MainActor
    func testCompactAccessibilityLayoutKeepsCardAndActionVerticallySeparated() throws {
        let content = EpisodeProgressRowLayout(
            isWatched: false,
            actionTitle: "Mark as watched",
            accessibilityLabel: "Mark as watched, Episode 12: A deliberately long episode title",
            onToggle: {},
            content: {
            VStack(alignment: .leading) {
                Rectangle().frame(height: 102)
                Text("Episode 12 · A deliberately long episode title that must remain readable")
                    .lineLimit(nil)
            }
        })
        .environment(\.dynamicTypeSize, .accessibility5)
        .frame(width: 272)

        let image = try XCTUnwrap(ImageRenderer(content: content).nsImage)
        XCTAssertEqual(image.size.width, 272, accuracy: 0.5)
        // The fixed 102-point card, spacing and 44-point action are separate vertical regions.
        XCTAssertGreaterThan(image.size.height, 154)
    }

    func testAccessibilityLabelIdentifiesActionEpisodeNumberAndTitle() {
        let translations = [
            ("Mark as watched", "Episode"), ("Đánh dấu đã xem", "Tập"),
            ("視聴済みにする", "エピソード"), ("시청 완료로 표시", "에피소드"),
            ("标记为已看", "第"), ("標示為已看", "第")
        ]
        for (action, episode) in translations {
            XCTAssertEqual(
                EpisodeProgressPresentation.actionAccessibilityLabel(
                    action: action, episodeLabel: episode, episodeNumber: 12, episodeName: "Finale"
                ),
                "\(action), \(episode) 12: Finale"
            )
        }
    }
}
#endif
