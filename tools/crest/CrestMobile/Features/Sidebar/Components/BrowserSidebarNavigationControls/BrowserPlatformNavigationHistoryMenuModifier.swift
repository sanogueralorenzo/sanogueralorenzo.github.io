import SwiftUI

/// iPadOS and iPhone keep a history control's menu as a SwiftUI context menu,
/// which UIKit presents from a long press or a secondary click.
struct BrowserPlatformNavigationHistoryMenuModifier: ViewModifier {
    /// The entries the menu lists, nearest first.
    let items: () -> [BrowserNavigationHistoryItem]
    let emptyTitle: LocalizedStringResource
    let choose: (BrowserNavigationHistoryItem) -> Void
    let showFullHistory: () -> Void

    func body(content: Content) -> some View {
        content.contextMenu {
            BrowserNavigationHistoryMenu(
                items: items(), emptyTitle: emptyTitle, action: choose, showFullHistory: showFullHistory
            )
            .tint(.primary)
        }
    }
}
