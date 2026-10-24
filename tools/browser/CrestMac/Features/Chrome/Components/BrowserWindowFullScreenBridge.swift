import SwiftUI

/// Reports whether the window hosting a scene is in full screen.
struct BrowserWindowFullScreenBridge: NSViewRepresentable {
    @Binding var isFullScreen: Bool

    func makeNSView(context: Context) -> BrowserWindowFullScreenHostView {
        let view = BrowserWindowFullScreenHostView()
        view.fullScreenChanged = { isFullScreen = $0 }
        return view
    }

    func updateNSView(
        _ nsView: BrowserWindowFullScreenHostView,
        context: Context
    ) {
        nsView.fullScreenChanged = { isFullScreen = $0 }
    }

    static func dismantleNSView(
        _ nsView: BrowserWindowFullScreenHostView,
        coordinator: ()
    ) {
        nsView.stopObservingWindow()
    }
}
