import SwiftUI

/// One direction of page history: the chevron, and the stack behind it.
struct BrowserSidebarNavigationHistoryControl: View {
    let direction: BrowserSidebarNavigationControl
    let port: BrowserSidebarNavigationPort
    let metrics: BrowserSidebarNavigationControlMetrics

    @Environment(\.browserShortcutBindings) private var bindings

    var body: some View {
        Button(action: navigate) {
            VStack(spacing: CrestSpacing.extraExtraSmall) {
                Image(systemName: direction.systemImage)
                    .font(metrics.historySymbolFont)
                BrowserShortcutHint(shortcut: direction.command.shortcut(in: bindings))
            }
            .frame(minWidth: metrics.controlSize.width, minHeight: metrics.controlSize.height)
        }
        .buttonStyle(CrestChromeButtonStyle(controlSize: nil))
        .accessibilityLabel(Text(direction.accessibilityLabel))
        .accessibilityIdentifier(direction.accessibilityIdentifier)
        .disabled(!direction.isAvailable(port))
        .help(Text(direction.accessibilityLabel))
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
