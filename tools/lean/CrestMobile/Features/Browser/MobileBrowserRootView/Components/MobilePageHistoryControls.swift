import SwiftUI

struct MobilePageHistoryControls: View {
    let pageActions: MobileSelectedPageActionPort?

    /// Opens History from the end of either history menu.
    let showHistory: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let pageActions, pageActions.isAvailable {
                availableHistoryControls(pageActions: pageActions)
            } else {
                historyButton(
                    title: "Back",
                    systemImage: "chevron.left",
                    enabled: false,
                    action: {}
                )
                .glassEffect(.regular.interactive(), in: .circle)
            }
        }
        .animation(
            CrestMotion.navigation.unlessReducingMotion(reduceMotion),
            value: pageActions?.canGoForward == true
        )
    }

    @ViewBuilder
    private func availableHistoryControls(
        pageActions: MobileSelectedPageActionPort
    ) -> some View {
        if pageActions.canGoForward {
            backAndForwardControls(pageActions: pageActions)
        } else {
            backButton(pageActions: pageActions)
                .glassEffect(.regular.interactive(), in: .circle)
                .transition(.opacity)
        }
    }

    private func backAndForwardControls(
        pageActions: MobileSelectedPageActionPort
    ) -> some View {
        HStack(spacing: 0) {
            backButton(pageActions: pageActions)
            Divider()
                .frame(height: MobileBrowserChromeLayout.historyDividerHeight)
                .opacity(MobileBrowserChromeLayout.historyDividerOpacity)
            forwardButton(pageActions: pageActions)
        }
        .padding(
            .horizontal,
            MobileBrowserChromeLayout.historyCapsuleHorizontalPadding
        )
        .glassEffect(.regular.interactive(), in: .capsule)
        .transition(.opacity)
    }

    private func backButton(
        pageActions: MobileSelectedPageActionPort
    ) -> some View {
        historyButton(
            title: "Back",
            systemImage: "chevron.left",
            enabled: pageActions.canGoBack,
            action: pageActions.goBack
        )
        .contextMenu {
            BrowserNavigationHistoryMenu(
                items: pageActions.backHistory,
                emptyTitle: "No Earlier Pages",
                action: pageActions.goBack(to:),
                showFullHistory: showHistory
            )
            .tint(.primary)
        }
    }

    private func forwardButton(
        pageActions: MobileSelectedPageActionPort
    ) -> some View {
        historyButton(
            title: "Forward",
            systemImage: "chevron.right",
            enabled: true,
            action: pageActions.goForward
        )
        .contextMenu {
            BrowserNavigationHistoryMenu(
                items: pageActions.forwardHistory,
                emptyTitle: "No Later Pages",
                action: pageActions.goForward(to:),
                showFullHistory: showHistory
            )
            .tint(.primary)
        }
    }

    private func historyButton(
        title: String,
        systemImage: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        MobileCompactIconButton(
            title: title,
            systemImage: systemImage,
            enabled: enabled,
            action: action
        )
    }
}
