import SwiftUI

/// Install behind controls before changing safe areas so the surface covers the title-bar strip.
struct BrowserWindowTitleBarSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> BrowserWindowTitleBarSurfaceView {
        BrowserWindowTitleBarSurfaceView()
    }

    func updateNSView(_ nsView: BrowserWindowTitleBarSurfaceView, context: Context) {}
}
