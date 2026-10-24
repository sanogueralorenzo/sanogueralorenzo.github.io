import SwiftUI

/// The Space header's overflow menu.
///
/// Every item is here exactly when the shell handed down a closure for it, so
/// the list is a statement about what this shell can do rather than about
/// which shell it is. Private browsing does not remove the items it disables —
/// it replaces them with the note that says why, which is the only way a
/// reader learns the feature exists at all.
struct BrowserSpaceHeaderActionsMenu: View {
    let isPrivateBrowsing: Bool
    let metrics: BrowserSpaceHeaderMetrics
    let actions: BrowserSpaceHeaderActions

    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    var body: some View {
        styledMenu
            .tint(.primary)
            .help("Space Actions")
            .accessibilityIdentifier("space-actions")
            .accessibilityLabel("Space actions")
    }

    /// `BorderlessButtonMenuStyle` is macOS's alone, and it is what keeps the
    /// ellipsis reading as a bare glyph rather than as a bordered popup. The
    /// compact shell's menu already draws that way without being asked.
    @ViewBuilder
    private var styledMenu: some View {
        #if os(macOS)
            menu
                .menuIndicator(.hidden)
                .menuStyle(.borderlessButton)
                .fixedSize()
        #else
            menu
        #endif
    }

    private var menu: some View {
        Menu {
            items
                .crestMenuActionLabelStyle()
        } label: {
            label
        }
        .crestMenuActionLabelStyle()
    }

    @ViewBuilder
    private var items: some View {
        Button("New Tab", systemImage: "plus", action: actions.openNewTab)

        if let openNewWindow = actions.openNewWindow, supportsMultipleWindows {
            Button(
                "New Window",
                systemImage: "macwindow.badge.plus",
                action: openNewWindow
            )
            .accessibilityIdentifier("new-browser-window")
        }

        Button(
            "New Folder",
            systemImage: "folder.badge.plus",
            action: actions.createFolder
        )

        Button(
            "History",
            systemImage: "clock.arrow.circlepath",
            action: actions.showHistory
        )

        if let showPasswords = actions.showPasswords {
            if isPrivateBrowsing {
                Label(
                    "Passwords Off in Private Browsing",
                    systemImage: "key.slash"
                )
                .foregroundStyle(.secondary)
            } else {
                Button("Passwords", systemImage: "key.fill", action: showPasswords)
            }
        }

        if isPrivateBrowsing,
            let closePrivateBrowsing = actions.closePrivateBrowsing
        {
            Button(
                "Close Private Tabs",
                systemImage: "xmark.square",
                role: .destructive,
                action: closePrivateBrowsing
            )
            .accessibilityIdentifier("close-private-tabs")
        }

        if let showSettings = actions.showSettings {
            Button("Settings", systemImage: "gearshape", action: showSettings)
                .accessibilityIdentifier("settings-button")
        }

        Button(
            "Clean Up Current Tabs",
            systemImage: "sparkles",
            action: actions.cleanup
        )
    }

    @ViewBuilder
    private var label: some View {
        let glyph = Image(systemName: "ellipsis")
            .font(metrics.actionsGlyph?.font)
            .frame(
                width: metrics.actionsControlSize,
                height: metrics.actionsControlSize
            )

        if metrics.expandsActionsHitArea {
            glyph.contentShape(.rect)
        } else {
            glyph
        }
    }
}
