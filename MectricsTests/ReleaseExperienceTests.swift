import XCTest
@testable import Mectrics

final class ReleaseExperienceTests: XCTestCase {
    func testCompletedOnboardingColdLaunchDoesNotPresentAWindow() {
        XCTAssertEqual(
            StartupPresentationPolicy.presentation(
                hasCompletedOnboarding: true,
                hasPendingRoutes: false
            ),
            .none
        )
    }

    func testFirstLaunchStillPresentsOnboarding() {
        XCTAssertEqual(
            StartupPresentationPolicy.presentation(
                hasCompletedOnboarding: false,
                hasPendingRoutes: false
            ),
            .onboarding
        )
    }

    func testColdLaunchDefersPresentationToPendingRoutes() {
        XCTAssertEqual(
            StartupPresentationPolicy.presentation(
                hasCompletedOnboarding: true,
                hasPendingRoutes: true
            ),
            .routes
        )
    }

    func testWhatsNewDoesNotInterruptAFirstInstall() {
        XCTAssertFalse(
            WhatsNewPolicy.shouldPresent(
                currentVersion: "1.0.0",
                storedVersion: nil
            )
        )
    }

    func testWhatsNewAppearsOnceForAChangedMarketingVersion() {
        XCTAssertTrue(
            WhatsNewPolicy.shouldPresent(
                currentVersion: "1.1.0",
                storedVersion: "1.0.0"
            )
        )
        XCTAssertFalse(
            WhatsNewPolicy.shouldPresent(
                currentVersion: "1.1.0",
                storedVersion: "1.1.0"
            )
        )
    }
}
