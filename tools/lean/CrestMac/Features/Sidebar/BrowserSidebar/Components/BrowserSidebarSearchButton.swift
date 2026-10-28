import SwiftUI

/// Opens the window's address and search palette from the navigation row.
struct BrowserSidebarSearchButton: View {
    let activate: () -> Void

    @Environment(\.browserShortcutBindings) private var bindings

    var body: some View {
        Button(action: activate) {
            VStack(spacing: CrestSpacing.extraExtraSmall) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: BrowserChromeLayout.sidebarNavigationSymbolPointSize))
                BrowserShortcutHint(shortcut: ShortcutCommand.openLocation.shortcut(in: bindings))
            }
            .frame(
                width: BrowserChromeLayout.sidebarNavigationControlHitTarget,
                height: BrowserChromeLayout.sidebarNavigationControlHitTarget
            )
        }
        .buttonStyle(CrestChromeButtonStyle(controlSize: nil))
        .accessibilityLabel("Address and search")
        .accessibilityHint("Opens the command palette")
        .accessibilityIdentifier("browser-search-control")
        .help("Search or Enter URL…")
    }
}
