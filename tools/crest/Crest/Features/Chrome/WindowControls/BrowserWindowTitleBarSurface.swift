import SwiftUI

/// Makes a stretch of empty chrome, such as the backdrop or the navigation
/// strip, act as the window's title bar (`BrowserWindowTitleBarSurfaceView`).
/// Place it behind the chrome's controls, and before any safe-area change, so
/// it covers the strip under the title bar.
struct BrowserWindowTitleBarSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> BrowserWindowTitleBarSurfaceView {
        BrowserWindowTitleBarSurfaceView()
    }

    func updateNSView(_ nsView: BrowserWindowTitleBarSurfaceView, context: Context) {}
}
