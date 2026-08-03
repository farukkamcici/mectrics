import AppKit

/// Decides when a menu bar agent is allowed a Dock icon.
///
/// Mectrics lives in the menu bar and launches with no Dock presence at all. It becomes
/// a regular app only while one of its own standard windows — Settings, the Attention
/// Log, Diagnostics, a metric detail, About, What's New, or onboarding — is on screen,
/// and it drops back the moment the last one closes.
///
/// The answer cannot be read off `NSApplication.windows`. That collection also holds the
/// window behind every status item, which is visible for the whole life of the app, so a
/// scan for "any visible window" is true forever and the icon never goes away. Closing
/// order makes it worse: `windowWillClose` runs *before* the window stops being visible,
/// so even a correct filter can see the window that is going away. Tracking the windows
/// the app opened on purpose avoids both traps, and it is testable without AppKit.
@MainActor
final class DockPresence {
    private var openWindowOwners: Set<ObjectIdentifier> = []
    private let apply: (NSApplication.ActivationPolicy) -> Void

    /// Pass `apply` to observe the decision instead of changing the real application.
    init(apply: ((NSApplication.ActivationPolicy) -> Void)? = nil) {
        self.apply = apply ?? { policy in NSApp.setActivationPolicy(policy) }
    }

    /// True while the app should own a Dock icon.
    var showsDockIcon: Bool { !openWindowOwners.isEmpty }

    /// Called by a window controller as it puts its window on screen.
    func windowDidOpen(_ owner: AnyObject) {
        let wasEmpty = openWindowOwners.isEmpty
        openWindowOwners.insert(ObjectIdentifier(owner))
        if wasEmpty { apply(.regular) }
    }

    /// Called by a window controller as its window closes. One controller owns at most
    /// one window, so its identity is the key.
    func windowWillClose(_ owner: AnyObject) {
        guard openWindowOwners.remove(ObjectIdentifier(owner)) != nil else { return }
        guard openWindowOwners.isEmpty else { return }
        // The window is still closing. Let AppKit finish before the app stops being a
        // regular application, or the last window can be left without a Dock tile to
        // animate into.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.openWindowOwners.isEmpty else { return }
            self.apply(.accessory)
        }
    }
}
