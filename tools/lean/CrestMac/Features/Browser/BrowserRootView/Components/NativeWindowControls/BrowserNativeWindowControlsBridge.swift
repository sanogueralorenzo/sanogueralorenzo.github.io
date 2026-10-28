import SwiftUI

struct BrowserNativeWindowControlsBridge: NSViewRepresentable {
    let isVisible: Bool

    func makeNSView(context: Context) -> BrowserNativeWindowControlsHostView {
        let view = BrowserNativeWindowControlsHostView()
        view.isVisible = isVisible
        return view
    }

    func updateNSView(
        _ nsView: BrowserNativeWindowControlsHostView,
        context: Context
    ) {
        nsView.isVisible = isVisible
        nsView.applyBrowserChrome()
    }

    static func dismantleNSView(
        _ nsView: BrowserNativeWindowControlsHostView,
        coordinator: Void
    ) {
        nsView.restoreWindowChrome()
    }
}
