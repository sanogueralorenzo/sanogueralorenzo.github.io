import SwiftUI

struct BrowserNativeWindowControlsBridge: NSViewRepresentable {
    let sidebarOffset: CGFloat

    func makeNSView(context: Context) -> BrowserNativeWindowControlsHostView {
        let view = BrowserNativeWindowControlsHostView()
        view.sidebarOffset = sidebarOffset
        return view
    }

    func updateNSView(
        _ nsView: BrowserNativeWindowControlsHostView,
        context: Context
    ) {
        nsView.sidebarOffset = sidebarOffset
    }

    static func dismantleNSView(
        _ nsView: BrowserNativeWindowControlsHostView,
        coordinator: Void
    ) {
        nsView.restoreWindowChrome()
    }
}
