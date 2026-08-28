#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import SmartMovieKit

final class DetailActionLayoutTests: XCTestCase {
    private let translations = [
        ["Trailer", "Favorite", "Watchlist"],
        ["Trailer", "Yêu thích", "Danh sách xem"],
        ["予告編", "お気に入り", "ウォッチリスト"],
        ["예고편", "즐겨찾기", "시청 목록"],
        ["预告片", "收藏", "想看"],
        ["預告片", "喜愛", "待看片單"]
    ]

    @MainActor
    func testNarrowLayoutPreservesAllLabelsByStackingInsteadOfCompressing() throws {
        for titles in translations {
            let actual = AdaptiveDetailGroup { self.pills(titles) }
            let expected = VStack(alignment: .leading, spacing: 12) { pills(titles) }
            try assertSamePixels(actual, expected, width: 180)
        }
    }

    @MainActor
    func testWideLayoutKeepsActionsOnOneRow() throws {
        let titles = translations[0]
        let actual = AdaptiveDetailGroup { self.pills(titles) }
        let expected = HStack(spacing: 12) { pills(titles) }.fixedSize(horizontal: true, vertical: true)
        try assertSamePixels(actual, expected, width: 900)
    }

    @MainActor
    func testFourthActionAlsoParticipatesInLayout() throws {
        let titles = translations[0] + ["Rate"]
        let actual = AdaptiveDetailGroup { self.pills(titles) }
        let expected = VStack(alignment: .leading, spacing: 12) { pills(titles) }
        try assertSamePixels(actual, expected, width: 300)
    }

    @MainActor
    func testLongSingleActionCanGrowVerticallyInsideTheViewport() throws {
        let title = "Danh sách xem — nội dung yêu thích để xem sau"
        let content = ActionPill(title: title, systemImage: "bookmark", prominent: false) {}
        let narrow = ImageRenderer(content: content.frame(width: 160))
        let wide = ImageRenderer(content: content.frame(width: 600))
        let narrowImage = try XCTUnwrap(narrow.nsImage)
        let wideImage = try XCTUnwrap(wide.nsImage)
        XCTAssertEqual(narrowImage.size.width, 160, accuracy: 0.5)
        XCTAssertGreaterThan(narrowImage.size.height, wideImage.size.height)
    }

    @MainActor
    func testCompactRightToLeftLayoutKeepsLeadingAlignment() throws {
        let titles = translations[0]
        let actual = AdaptiveDetailGroup { self.pills(titles) }
            .environment(\.layoutDirection, .rightToLeft)
        let expected = VStack(alignment: .leading, spacing: 12) { pills(titles) }
            .environment(\.layoutDirection, .rightToLeft)
        try assertSamePixels(actual, expected, width: 180)
    }

    @MainActor
    func testActionPillMaintainsMinimumTapHeight() throws {
        let content = ActionPill(title: "Rate", systemImage: "star", prominent: false) {}
        let renderer = ImageRenderer(content: content)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(renderer.nsImage).size.height, 44)
    }

    @MainActor
    func testLargeMetadataValuesStackInsteadOfBreakingDigits() throws {
        let metadata = {
            Group {
                RatingBadge(rating: 8.4)
                Text("1999")
                Text("2h 0m")
            }
            .font(.system(size: 48))
        }
        let actual = AdaptiveDetailGroup(content: metadata)
        let expected = VStack(alignment: .leading, spacing: 12, content: metadata)
        try assertSamePixels(actual, expected, width: 200)
    }

    @MainActor
    private func pills(_ titles: [String]) -> some View {
        ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
            ActionPill(title: title, systemImage: index == 0 ? "play.fill" : "heart", prominent: index == 0) {}
        }
    }

    @MainActor
    private func assertSamePixels<Actual: View, Expected: View>(
        _ actual: Actual,
        _ expected: Expected,
        width: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let actualRenderer = ImageRenderer(content: actual.frame(width: width, alignment: .leading))
        let expectedRenderer = ImageRenderer(content: expected.frame(width: width, alignment: .leading))
        let actualImage = try XCTUnwrap(actualRenderer.cgImage, file: file, line: line)
        let expectedImage = try XCTUnwrap(expectedRenderer.cgImage, file: file, line: line)
        XCTAssertEqual(actualImage.width, expectedImage.width, file: file, line: line)
        XCTAssertEqual(actualImage.height, expectedImage.height, file: file, line: line)
        let actualPixels = try XCTUnwrap(actualImage.dataProvider?.data, file: file, line: line)
        let expectedPixels = try XCTUnwrap(expectedImage.dataProvider?.data, file: file, line: line)
        XCTAssertTrue(actualPixels == expectedPixels, "Layout differs from uncompressed labels", file: file, line: line)
    }
}
#endif
