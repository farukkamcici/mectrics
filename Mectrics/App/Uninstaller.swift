import AppKit

/// Removes Mectrics and everything it stored, from inside the running app.
///
/// An app cannot delete itself and then keep running long enough to finish the job, so
/// the work is split. Mectrics does the two things only a live app can do — unregister
/// its login item, and stop writing — then hands a detached shell helper its own process
/// id. The helper waits for that process to disappear before deleting anything.
///
/// The wait is not a nicety. A running Mectrics flushes its preferences on the way out,
/// so deleting the plist first simply loses the race: the file comes back a moment later,
/// and the next launch skips onboarding as if nothing had happened.
enum Uninstaller {

    /// Everything Mectrics writes outside its own bundle.
    ///
    /// `~/Library/Containers/com.mectrics.app.widget` is deliberately absent. It belongs
    /// to containermanagerd, which refuses deletion without Full Disk Access — a
    /// permission this app does not ask for and should not start asking for to be able
    /// to remove itself. It holds one cached snapshot, and macOS reclaims the container
    /// once the extension is gone.
    static func dataPaths(home: URL) -> [URL] {
        let library = home.appending(path: "Library")
        return [
            library.appending(path: "Preferences/com.mectrics.app.plist"),
            library.appending(path: "Group Containers/group.com.mectrics.app"),
            library.appending(path: "Application Support/Mectrics"),
            library.appending(path: "Caches/com.mectrics.app"),
            library.appending(path: "Caches/com.mectrics.app.sparkle"),
            library.appending(path: "HTTPStorages/com.mectrics.app"),
            library.appending(path: "Saved Application State/com.mectrics.app.savedState")
        ]
    }

    /// The helper. Single-quoted paths, with any embedded quote escaped the POSIX way,
    /// because a home directory may contain spaces and is not ours to assume about.
    static func helperScript(pid: Int32, paths: [URL]) -> String {
        let quoted = paths
            .map { "  " + shellQuoted($0.path(percentEncoded: false)) }
            .joined(separator: "\n")
        return """
        #!/bin/sh
        # Written by Mectrics to remove itself. Deletes itself when finished.

        # Wait for Mectrics to exit; it rewrites its preferences as it terminates.
        i=0
        while kill -0 \(pid) 2>/dev/null; do
          if [ $i -ge 100 ]; then
            rm -f "$0"
            exit 1
          fi
          sleep 0.1
          i=$((i + 1))
        done

        # Drop the domain through cfprefsd first, or its cache writes the file back.
        defaults delete com.mectrics.app 2>/dev/null

        for target in \\
        \(quoted)
        do
          rm -rf "$target" 2>/dev/null
        done

        rm -f "$0"
        """
    }

    static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Unregisters the login item, spawns the helper, and terminates the app.
    ///
    /// Returns `false` if the helper could not be written or launched, in which case
    /// nothing has been deleted and the app stays running.
    @MainActor
    @discardableResult
    static func performUninstall(
        home: URL = URL(filePath: NSHomeDirectory()),
        bundle: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default,
        terminate: @MainActor () -> Void = { NSApp.terminate(nil) }
    ) -> Bool {
        // Refuse to erase user data when the bundle itself cannot be removed, such as
        // when Mectrics is launched directly from a read-only disk image.
        guard fileManager.isDeletableFile(
            atPath: bundle.path(percentEncoded: false)
        ) else {
            return false
        }

        let script = helperScript(
            pid: ProcessInfo.processInfo.processIdentifier,
            paths: [bundle] + dataPaths(home: home)
        )
        let scriptURL = URL(filePath: NSTemporaryDirectory())
            .appending(path: "mectrics-uninstall-\(UUID().uuidString).sh")

        do {
            // The helper lives outside the bundle it is about to delete.
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Uninstall failed to start: \(error.localizedDescription)")
            return false
        }

        // A deleted app cannot unregister itself later, so this has to happen while
        // Mectrics is still alive.
        let wasLoginItemEnabled = LoginItem.isEnabled
        guard LoginItem.setEnabled(false) else {
            try? fileManager.removeItem(at: scriptURL)
            return false
        }

        do {
            let process = Process()
            process.executableURL = URL(filePath: "/bin/sh")
            process.arguments = [scriptURL.path(percentEncoded: false)]
            try process.run()
        } catch {
            // The helper never started, so restoring the login item leaves the Mac as
            // close as possible to the state it was in before the attempt.
            try? fileManager.removeItem(at: scriptURL)
            if wasLoginItemEnabled {
                LoginItem.setEnabled(true)
            }
            NSLog("Uninstall failed to start: \(error.localizedDescription)")
            return false
        }

        terminate()
        return true
    }
}
