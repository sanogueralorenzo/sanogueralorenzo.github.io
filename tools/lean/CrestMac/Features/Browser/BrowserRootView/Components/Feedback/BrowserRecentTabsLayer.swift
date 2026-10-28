import SwiftUI

/// The recent tabs a held Most Recent Tab shortcut shows, centred over the
/// window and shrunk only as far as the window needs.
struct BrowserRecentTabsLayer: View {
    let chrome: BrowserChromeState

    var body: some View {
        if let model = chrome.recentTabs {
            GeometryReader { proxy in
                let natural = RecentTabSwitcherMetrics.naturalSize(for: model.session.items)
                let available = max(proxy.size.width - RecentTabSwitcherMetrics.windowMargin * 2, 0)
                RecentTabSwitcherView(model: model, scale: natural.width > available ? available / natural.width : 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .transition(.opacity)
        }
    }
}
