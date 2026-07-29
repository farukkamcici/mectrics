import AppKit
import Sparkle

/// Owns Sparkle's standard, signature-verifying update experience. Automatic checks
/// are disabled in Info.plist; network access begins only after the user chooses the
/// explicit Check for Updates command.
@MainActor
final class UpdateController: NSObject, NSMenuItemValidation {
    let standardController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

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
        return String(
            localized: "about.updates.manualSigned",
            defaultValue: "Manual, signature-verified checks"
        )
    }
}
