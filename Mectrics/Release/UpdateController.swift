import AppKit
import Sparkle

/// Owns Sparkle's standard, signature-verifying update experience.
///
/// Info.plist leaves automatic checks off, so a build that is never asked never reaches
/// the network. Turning them on is the user's decision, taken once in onboarding or in
/// Settings, and it changes only *when* the appcast is fetched. What the request carries
/// does not change: `SUEnableSystemProfiling` stays off, so no hardware or usage
/// information is attached to it, and an update is never downloaded or installed on its
/// own — Mectrics says one is available and the user decides.
@MainActor
final class UpdateController: NSObject, NSMenuItemValidation {
    let standardController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    override init() {
        super.init()
        // Checking is not installing. Sparkle can do the whole thing unattended; for an
        // app that promises to stay out of the way, finding the update is the helpful
        // part and applying it is the user's call.
        standardController.updater.automaticallyDownloadsUpdates = false
    }

    /// Whether Sparkle looks for a new version on its own schedule.
    var checksAutomatically: Bool {
        get { standardController.updater.automaticallyChecksForUpdates }
        set { standardController.updater.automaticallyChecksForUpdates = newValue }
    }

    @objc func checkForUpdates(_ sender: Any?) {
        standardController.checkForUpdates(sender)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        standardController.updater.canCheckForUpdates
    }

    static var localizedStatus: String {
        let bundle = Bundle.main
        let feed = bundle.object(
            forInfoDictionaryKey: "SUFeedURL"
        ) as? String
        let publicKey = bundle.object(
            forInfoDictionaryKey: "SUPublicEDKey"
        ) as? String
        guard let feed, URL(string: feed)?.scheme == "https",
              let publicKey, !publicKey.isEmpty else {
            return String(
                localized: "about.updates.unavailable",
                defaultValue: "Not configured in this build"
            )
        }
        return UserDefaults.standard.bool(forKey: automaticChecksKey)
            ? String(
                localized: "about.updates.automaticSigned",
                defaultValue: "Automatic, signature-verified checks"
            )
            : String(
                localized: "about.updates.manualSigned",
                defaultValue: "Manual, signature-verified checks"
            )
    }

    /// Sparkle's own preference key. Reading it keeps `localizedStatus` static without a
    /// second copy of the setting that could drift from the updater's.
    static let automaticChecksKey = "SUEnableAutomaticChecks"
}
