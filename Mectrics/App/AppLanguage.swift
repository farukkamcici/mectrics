import AppKit

/// Languages shipped by Mectrics, plus the macOS language preference.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case turkish = "tr"
    case russian = "ru"
    case spanish = "es"
    case french = "fr"
    case portugueseBrazil = "pt-BR"

    private static let preferenceKey = "app.language"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .system:
            return String(localized: "language.system", defaultValue: "System Default")
        case .english:
            return String(localized: "language.english", defaultValue: "English")
        case .turkish:
            return String(localized: "language.turkish", defaultValue: "Turkish")
        case .russian:
            return String(localized: "language.russian", defaultValue: "Russian")
        case .spanish:
            return String(localized: "language.spanish", defaultValue: "Spanish")
        case .french:
            return String(localized: "language.french", defaultValue: "French")
        case .portugueseBrazil:
            return String(
                localized: "language.portugueseBrazil",
                defaultValue: "Portuguese (Brazil)"
            )
        }
    }

    /// Captured before a Settings change, and retained until the process relaunches.
    static let selectionAtLaunch = selected()

    static func selected(in defaults: UserDefaults = .standard) -> AppLanguage {
        guard let rawValue = defaults.string(forKey: preferenceKey),
              let language = AppLanguage(rawValue: rawValue) else {
            return .system
        }
        return language
    }

    static func apply(_ language: AppLanguage, to defaults: UserDefaults = .standard) {
        if language == .system {
            defaults.removeObject(forKey: preferenceKey)
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set(language.rawValue, forKey: preferenceKey)
            defaults.set([language.rawValue], forKey: "AppleLanguages")
        }
        defaults.synchronize()
    }
}

/// Starts a small process outside the app, waits for this process to exit, then opens
/// the same bundle again so a changed localization is loaded from the beginning.
enum AppRelauncher {
    static func helperScript(pid: Int32, bundle: URL) -> String {
        """
        i=0
        while kill -0 \(pid) 2>/dev/null && [ $i -lt 100 ]; do
          sleep 0.1
          i=$((i + 1))
        done
        [ $i -lt 100 ] || exit 1
        /usr/bin/open -n \(Uninstaller.shellQuoted(bundle.path(percentEncoded: false)))
        """
    }

    @MainActor
    @discardableResult
    static func relaunch(
        bundle: URL = Bundle.main.bundleURL,
        terminate: @MainActor () -> Void = { NSApp.terminate(nil) }
    ) -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = [
            "-c",
            helperScript(
                pid: ProcessInfo.processInfo.processIdentifier,
                bundle: bundle
            )
        ]

        do {
            try process.run()
            terminate()
            return true
        } catch {
            NSLog("Relaunch failed to start: \(error.localizedDescription)")
            return false
        }
    }
}
