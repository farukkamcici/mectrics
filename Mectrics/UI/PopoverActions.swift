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

/// Shared bottom bar: app-level navigation sits quietly below the popover's own
/// action, and rare or irreversible items stay behind the menu so they cannot be hit
/// by accident.
struct PopoverActionBar<MenuItems: View>: View {
    let onOpenSettings: () -> Void
    @ViewBuilder var menuItems: () -> MenuItems

    init(
        onOpenSettings: @escaping () -> Void,
        @ViewBuilder menuItems: @escaping () -> MenuItems = { EmptyView() }
    ) {
        self.onOpenSettings = onOpenSettings
        self.menuItems = menuItems
    }

    var body: some View {
        HStack {
            Button(action: onOpenSettings) {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
            Spacer()
            Menu {
                menuItems()
                Button("Quit Mectrics") {
                    NSApp.terminate(nil)
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("More actions")
        }
        .font(.callout)
    }
}
