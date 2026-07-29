import AppKit
import SwiftUI

extension View {
    /// Hides the keyboard focus ring, unless the user navigates by keyboard.
    ///
    /// SwiftUI focuses the first control in a window or popover as it appears, so a
    /// row or button the user never chose is drawn as selected. Clearing the responder
    /// once is not enough: SwiftUI re-establishes focus during its own first layout
    /// pass, after any such cleanup has run.
    ///
    /// The ring still appears for anyone using Full Keyboard Access, where it is the
    /// only way to tell what a key press will act on.
    func quietFocusRing() -> some View {
        focusEffectDisabled(!NSApp.isFullKeyboardAccessEnabled)
    }
}

extension NSWindow {
    /// Presents without a keyboard focus ring around the first control.
    ///
    /// AppKit hands first responder to the leading focusable view when a window or
    /// popover appears, so a stepper or button the user never chose is drawn as
    /// selected. Clearing it once on presentation removes that false selection;
    /// Tab and Full Keyboard Access still move focus normally afterwards.
    func clearInitialFocus() {
        // SwiftUI installs its own responders during the first layout pass, so this
        // has to run after the window has finished coming up.
        DispatchQueue.main.async { [weak self] in
            self?.makeFirstResponder(nil)
        }
    }
}
