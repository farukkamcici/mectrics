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

    /// An upgrade with nothing written for it must not interrupt anyone. The window
    /// previously showed one hardcoded list forever, so upgrading to any version was
    /// greeted with news from an old one.
    func testAnUpgradeWithoutNotesIsNotAnnounced() {
        XCTAssertFalse(
            WhatsNewPolicy.shouldPresent(
                currentVersion: "9.9.9",
                storedVersion: "1.0.0",
                hasNotes: false
            )
        )
    }

    func testReleaseNotesBelongToTheVersionTheyShippedIn() {
        XCTAssertFalse(ReleaseHighlights.notes(for: "1.6.0").isEmpty)
        XCTAssertFalse(ReleaseHighlights.notes(for: "1.6.1").isEmpty)
        XCTAssertFalse(ReleaseHighlights.notes(for: "1.5.0").isEmpty)
        XCTAssertTrue(ReleaseHighlights.notes(for: "1.4.0").isEmpty)
        XCTAssertTrue(ReleaseHighlights.notes(for: "0.0.0").isEmpty)
    }

    /// The notes shown are the running build's, so shipping a version without adding
    /// notes for it is visible here rather than to a user after an update.
    func testTheRunningVersionHasReleaseNotes() {
        XCTAssertFalse(
            ReleaseHighlights.current.isEmpty,
            "Add release notes for \(Bundle.main.marketingVersion) to ReleaseHighlights"
        )
    }

    /// A patch does not get a window of its own: it repeats what the minor release
    /// brought and appends its own line, so skipping 1.6.0 does not mean missing it.
    func testAPatchCarriesTheMinorReleaseNotesAndAddsToThem() {
        let minor = ReleaseHighlights.notes(for: "1.6.0").map(\.id)
        let patch = ReleaseHighlights.notes(for: "1.6.1").map(\.id)
        XCTAssertEqual(Array(patch.prefix(minor.count)), minor)
        XCTAssertGreaterThan(patch.count, minor.count)
    }

    func testReleaseNoteIdentifiersAreUnique() {
        for version in ["1.5.0", "1.6.0", "1.6.1"] {
            let ids = ReleaseHighlights.notes(for: version).map(\.id)
            XCTAssertEqual(ids.count, Set(ids).count, version)
        }
    }

    // MARK: - Asking to use the network

    /// The question belongs on a launch where Mectrics has nothing else to say.
    func testTheUpdateQuestionWaitsForAQuietLaunch() {
        XCTAssertTrue(
            UpdatePermissionPolicy.shouldAsk(
                presentation: .none, hasAnswered: false, isRunningTests: false
            )
        )
        for presentation in [StartupPresentation.onboarding, .whatsNew, .routes] {
            XCTAssertFalse(
                UpdatePermissionPolicy.shouldAsk(
                    presentation: presentation, hasAnswered: false, isRunningTests: false
                ),
                "\(presentation) already has the user's attention"
            )
        }
    }

    /// Declining is an answer. Asking again would make "no" mean "ask me every launch".
    func testAnAnsweredQuestionIsNeverAskedAgain() {
        XCTAssertFalse(
            UpdatePermissionPolicy.shouldAsk(
                presentation: .none, hasAnswered: true, isRunningTests: false
            )
        )
    }

    /// The XCTest host launches the real app. A modal question there blocks the whole
    /// run instead of failing it, so the suite hangs and takes the screen with it.
    func testTheQuestionIsNeverAskedUnderTest() {
        XCTAssertFalse(
            UpdatePermissionPolicy.shouldAsk(
                presentation: .none, hasAnswered: false, isRunningTests: true
            )
        )
        XCTAssertTrue(
            UpdatePermissionPolicy.isRunningTests,
            "This suite is running under XCTest, so the guard must see it"
        )
    }
}
