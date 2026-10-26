import SwiftUI

/// One direction of page history as a side toolbar item: a tap walks it and a
/// touch and hold lists it, as a bar's back button does.
///
/// The sidebar strip's control hangs its list off a context menu, which a bar
/// item turns into the menu a tap opens; a menu with a primary action keeps
/// the tap for the step.
struct MobileHistoryToolbarControl: View {
    let direction: BrowserSidebarNavigationControl
    let port: BrowserSidebarNavigationPort

    var body: some View {
        Menu {
            BrowserNavigationHistoryMenu(
                items: direction.history(port),
                emptyTitle: direction.emptyHistoryTitle,
                action: { direction.navigateToItem(port, $0) },
                showFullHistory: port.showHistory
            )
        } label: {
            Label {
                Text(direction.accessibilityLabel)
            } icon: {
                Image(systemName: direction.systemImage)
            }
        } primaryAction: {
            direction.navigate(port)
        }
        .disabled(!direction.isAvailable(port))
        .accessibilityIdentifier(direction.accessibilityIdentifier)
    }
}
