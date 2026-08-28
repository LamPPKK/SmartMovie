import XCTest
#if os(macOS)
import SwiftUI
#endif
@testable import SmartMovieKit

@MainActor
final class AccountRatingOptionsTests: XCTestCase {
    func testMenuOffersEveryContractValueExactlyOnceInAscendingOrder() {
        XCTAssertEqual(AccountRatingOptions.values, [
            0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5,
            5.5, 6, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10
        ])
    }

    func testHalfStepLabelsFollowAllSixShippedLocalesWithoutRounding() {
        for identifier in ["en-US", "ja-JP", "ko-KR", "zh-Hans", "zh-Hant"] {
            let locale = Locale(identifier: identifier)
            XCTAssertEqual(AccountRatingOptions.label(for: 0.5, locale: locale), "0.5 / 10", identifier)
            XCTAssertEqual(AccountRatingOptions.label(for: 9.5, locale: locale), "9.5 / 10", identifier)
            XCTAssertEqual(AccountRatingOptions.label(for: 10, locale: locale), "10 / 10", identifier)
        }
        let vietnamese = Locale(identifier: "vi-VN")
        XCTAssertEqual(AccountRatingOptions.label(for: 0.5, locale: vietnamese), "0,5 / 10")
        XCTAssertEqual(AccountRatingOptions.label(for: 9.5, locale: vietnamese), "9,5 / 10")
        XCTAssertEqual(AccountRatingOptions.label(for: 10, locale: vietnamese), "10 / 10")
    }

    #if os(macOS)
    func testRenderedContentContainsAllChoicesAndOnlyOffersRemovalForExistingRating() throws {
        let labels = [
            "0.5 / 10", "1 / 10", "1.5 / 10", "2 / 10", "2.5 / 10", "3 / 10", "3.5 / 10",
            "4 / 10", "4.5 / 10", "5 / 10", "5.5 / 10", "6 / 10", "6.5 / 10", "7 / 10",
            "7.5 / 10", "8 / 10", "8.5 / 10", "9 / 10", "9.5 / 10", "10 / 10"
        ]
        for currentRating: Double? in [nil, 0.5] {
            let actual = VStack(alignment: .leading, spacing: 0) {
                AccountRatingOptions(currentRating: currentRating) { _ in }
            }
            let expected = VStack(alignment: .leading, spacing: 0) {
                ForEach(labels, id: \.self) { label in Button(label) {} }
                if currentRating != nil { Button("Remove rating", role: .destructive) {} }
            }
            let actualRenderer = ImageRenderer(content: actual
                .environment(\.locale, Locale(identifier: "en-US"))
                .buttonStyle(.borderless))
            let expectedRenderer = ImageRenderer(content: expected
                .environment(\.locale, Locale(identifier: "en-US"))
                .buttonStyle(.borderless))
            let actualImage = try XCTUnwrap(actualRenderer.cgImage)
            let expectedImage = try XCTUnwrap(expectedRenderer.cgImage)
            XCTAssertGreaterThan(actualImage.height, 200)
            XCTAssertEqual(actualImage.width, expectedImage.width)
            XCTAssertEqual(actualImage.height, expectedImage.height)
            XCTAssertEqual(
                try XCTUnwrap(actualImage.dataProvider?.data) as Data,
                try XCTUnwrap(expectedImage.dataProvider?.data) as Data
            )
        }
    }
    #endif
}
