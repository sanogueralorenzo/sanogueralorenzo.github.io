import SwiftUI

/// One page's back or forward stack, as context-menu items, ending with the way
/// to History.
///
/// Every iOS and iPadOS chrome that hangs history off a navigation control
/// uses it: the sidebar strip and the compact shell's floating history capsule.
/// macOS builds the same menu in AppKit (`BrowserNavigationHistoryMenuTriggerView`).
/// The engines hand over only the nearest entries, so the menu stays short
/// however long the page's own history grows.
struct BrowserNavigationHistoryMenu: View {
    let items: [BrowserNavigationHistoryItem]
    let emptyTitle: LocalizedStringResource
    let action: (BrowserNavigationHistoryItem) -> Void

    /// Opens History, which keeps every visit the menu leaves out.
    let showFullHistory: () -> Void

    var body: some View {
        Group {
            if items.isEmpty {
                Text(emptyTitle)
            } else {
                ForEach(items) { item in
                    Button {
                        action(item)
                    } label: {
                        Label(item.title, systemImage: "globe")
                    }
                }
            }
            Divider()
            Button("Show Full History", systemImage: ShortcutCommand.showHistory.symbol, action: showFullHistory)
        }
        .crestMenuActionLabelStyle()
    }
}
