import Foundation
import XCTest
@testable import SmartMovieKit

@MainActor
final class AdultContentControllerTests: XCTestCase {
    func testConfigurationRequiresAgeConfirmationAndMatchingSixDigitPin() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let controller = AdultContentController(defaults: defaults)

        XCTAssertFalse(controller.configure(pin: "123456", confirmation: "123456", ageConfirmed: false))
        XCTAssertFalse(controller.isEnabled)
        XCTAssertFalse(controller.includeAdult)

        XCTAssertFalse(controller.configure(pin: "12345", confirmation: "12345", ageConfirmed: true))
        XCTAssertFalse(controller.configure(pin: "123456", confirmation: "654321", ageConfirmed: true))

        XCTAssertTrue(controller.configure(pin: "123456", confirmation: "123456", ageConfirmed: true))
        XCTAssertTrue(controller.isEnabled)
        XCTAssertTrue(controller.includeAdult)
    }

    func testFiveFailedUnlocksLockTheControllerForFiveMinutes() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        var currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        let controller = AdultContentController(defaults: defaults, now: { currentDate })
        XCTAssertTrue(controller.configure(pin: "123456", confirmation: "123456", ageConfirmed: true))
        controller.lock()

        for _ in 0..<4 {
            XCTAssertFalse(controller.unlock(pin: "000000"))
            XCTAssertFalse(controller.isLocked)
        }
        XCTAssertFalse(controller.unlock(pin: "000000"))
        XCTAssertTrue(controller.isLocked)
        XCTAssertFalse(controller.unlock(pin: "123456"))

        currentDate.addTimeInterval(5 * 60 + 1)
        XCTAssertFalse(controller.isLocked)
        XCTAssertTrue(controller.unlock(pin: "123456"))
        XCTAssertTrue(controller.includeAdult)
    }

    private var defaultsSuite: String { "AdultContentControllerTests.\(name)" }

    private func makeDefaults() throws -> UserDefaults {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        defaults.removePersistentDomain(forName: defaultsSuite)
        return defaults
    }
}
