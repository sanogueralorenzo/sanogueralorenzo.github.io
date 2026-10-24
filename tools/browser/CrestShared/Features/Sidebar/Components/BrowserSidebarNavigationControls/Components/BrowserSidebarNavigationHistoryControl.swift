import SwiftUI

/// One direction of page history: the chevron, and the stack behind it.
struct BrowserSidebarNavigationHistoryControl: View {
    let direction: BrowserSidebarNavigationControl
    let port: BrowserSidebarNavigationPort
    let metrics: BrowserSidebarNavigationControlMetrics

    var body: some View {
        Button(action: navigate) {
            Image(systemName: direction.systemImage)
                .font(metrics.historySymbolFont)
        }
        .accessibilityLabel(Text(direction.accessibilityLabel))
        .accessibilityIdentifier(direction.accessibilityIdentifier)
        .disabled(!direction.isAvailable(port))
        .help(Text(direction.tooltip))
        .modifier(
            BrowserPlatformNavigationHistoryMenuModifier(
                items: { direction.history(port) },
                emptyTitle: direction.emptyHistoryTitle,
                choose: navigate(to:),
                showFullHistory: port.showHistory
            )
        )
    }

    private func navigate() {
        direction.navigate(port)
    }

    private func navigate(to item: BrowserNavigationHistoryItem) {
        direction.navigateToItem(port, item)
    }
}
