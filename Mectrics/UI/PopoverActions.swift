import AppKit
import SwiftUI

/// The action a popover exists to offer — opening Activity Monitor from Memory,
/// Storage settings from Disk, the Attention Log from Compact Health.
///
/// Full width so it reads as this panel's own action rather than one option among
/// several, but ordinary weight: the readings above it are the point of the popover.
struct PopoverPrimaryButton: View {
    let title: String
    let symbolName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbolName)
                .frame(maxWidth: .infinity)
        }
    }
}

/// Shared bottom bar: app-level actions sit quietly below the popover's own action.
///
/// Quit keeps a destructive tint so it reads as the one irreversible item here,
/// without being hidden behind a menu that would hold a single command.
struct PopoverActionBar: View {
    let onOpenSettings: () -> Void

    var body: some View {
        HStack {
            Button(action: onOpenSettings) {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color(nsColor: .systemRed))
        }
        .font(.callout)
    }
}
