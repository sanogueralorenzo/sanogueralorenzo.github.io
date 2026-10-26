import SwiftUI

// MARK: - Types

/// The trigger a history control's accessibility action opens its menu from.
@MainActor
final class BrowserNavigationHistoryMenuAnchor {
    weak var view: BrowserNavigationHistoryMenuTriggerView?
}

/// macOS hangs a history control's menu off an AppKit trigger rather than a
/// SwiftUI context menu, so the open menu stays AppKit's alone
/// (`BrowserNavigationHistoryMenuTriggerView` says why). Show Menu still opens
/// it for an accessibility client.
struct BrowserPlatformNavigationHistoryMenuModifier: ViewModifier {
    /// The entries the menu lists, nearest first, read when it opens.
    let items: () -> [BrowserNavigationHistoryItem]
    let emptyTitle: LocalizedStringResource
    let choose: (BrowserNavigationHistoryItem) -> Void
    let showFullHistory: () -> Void

    @State private var anchor = BrowserNavigationHistoryMenuAnchor()

    func body(content: Content) -> some View {
        content
            .overlay {
                BrowserNavigationHistoryMenuTrigger(
                    anchor: anchor, items: items, emptyTitle: emptyTitle, choose: choose,
                    showFullHistory: showFullHistory
                )
                .accessibilityHidden(true)
            }
            .accessibilityAction(.showMenu) { anchor.view?.presentMenuBelowControl() }
    }
}
