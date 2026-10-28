import SwiftUI

/// Reports whether the window hosting the browser holds key focus.
struct BrowserWindowFocusBridge: NSViewRepresentable {
    @Binding var isWindowFocused: Bool

    func makeNSView(context: Context) -> BrowserWindowFocusHostView {
        let view = BrowserWindowFocusHostView()
        view.focusChanged = { isWindowFocused = $0 }
        return view
    }

    func updateNSView(
        _ nsView: BrowserWindowFocusHostView,
        context: Context
    ) {
        nsView.focusChanged = { isWindowFocused = $0 }
    }

    static func dismantleNSView(
        _ nsView: BrowserWindowFocusHostView,
        coordinator: ()
    ) {
        nsView.stopObservingWindow()
    }
}
