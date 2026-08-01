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

    /// Sparkle installs an update by quitting the app and starting it again, so the
    /// launch path — not reopen — is where an upgrade is noticed. A menu bar agent has
    /// no Dock icon, so waiting for reopen meant the notes were never shown at all.
    func testLaunchAfterAnUpgradePresentsWhatsNew() {
        XCTAssertEqual(
            StartupPresentationPolicy.presentation(
                hasCompletedOnboarding: true,
                hasPendingRoutes: false,
                hasUpgraded: true
            ),
            .whatsNew
        )
    }

    /// A `mectrics://` link is an errand the user asked for; release notes are not.
    func testAnOpenedLinkOutranksTheUpgradeNotes() {
        XCTAssertEqual(
            StartupPresentationPolicy.presentation(
                hasCompletedOnboarding: true,
                hasPendingRoutes: true,
                hasUpgraded: true
            ),
            .routes
        )
    }

    /// A first install has no previous version to have upgraded from, and onboarding
    /// owns that launch regardless.
    func testFirstInstallNeverShowsUpgradeNotes() {
        XCTAssertEqual(
            StartupPresentationPolicy.presentation(
                hasCompletedOnboarding: false,
                hasPendingRoutes: false,
                hasUpgraded: true
            ),
            .onboarding
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
