import SwiftUI

struct BrowserNativeWindowControlsBridge: NSViewRepresentable {
    let isVisible: Bool
    var sidebarOnRight = false
    var sidebarWidth: CGFloat = BrowserChromeLayout.sidebarIdealWidth

    func makeNSView(context: Context) -> BrowserNativeWindowControlsHostView {
        let view = BrowserNativeWindowControlsHostView()
        view.sidebarOnRight = sidebarOnRight
        view.sidebarWidth = sidebarWidth
        view.isVisible = isVisible
        return view
    }

    func updateNSView(
        _ nsView: BrowserNativeWindowControlsHostView,
        context: Context
    ) {
        nsView.sidebarWidth = sidebarWidth
        nsView.isVisible = isVisible
        guard nsView.sidebarOnRight != sidebarOnRight else {
            nsView.applyBrowserChrome()
            return
        }
        // The sidebar crosses the window in this update's animation, and the
        // controls go with it on the same curve.
        context.animate {
            nsView.moveWindowControls(sidebarOnRight: sidebarOnRight)
        } completion: {
            nsView.finishMovingWindowControls()
        }
    }

    static func dismantleNSView(
        _ nsView: BrowserNativeWindowControlsHostView,
        coordinator: Void
    ) {
        nsView.restoreWindowChrome()
    }
}
