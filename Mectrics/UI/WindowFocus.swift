import AppKit

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
