import SwiftUI

/// Follows the sidebar's animation while keeping its closing edge immediate.
struct BrowserWindowControlsPresentation: @MainActor AnimatableModifier {
    let showsSidebar: Bool
    private var sidebarReveal: CGFloat

    init(showsSidebar: Bool) {
        self.showsSidebar = showsSidebar
        sidebarReveal = showsSidebar ? 1 : 0
    }

    var animatableData: CGFloat {
        get { sidebarReveal }
        set { sidebarReveal = newValue }
    }

    func body(content: Content) -> some View {
        content.background(BrowserNativeWindowControlsBridge(opacity: controlsOpacity))
    }

    private var controlsOpacity: CGFloat {
        guard showsSidebar else { return 0 }
        // Finish the fade with the visible slide, before the spring's settling tail.
        let fadeStart: CGFloat = 0.90
        let fadeEnd: CGFloat = 0.98
        return min(1, max(0, (sidebarReveal - fadeStart) / (fadeEnd - fadeStart)))
    }
}

struct BrowserNativeWindowControlsBridge: NSViewRepresentable {
    let opacity: CGFloat

    func makeNSView(context: Context) -> BrowserNativeWindowControlsHostView {
        let view = BrowserNativeWindowControlsHostView()
        view.controlsOpacity = opacity
        return view
    }

    func updateNSView(
        _ nsView: BrowserNativeWindowControlsHostView,
        context: Context
    ) {
        nsView.controlsOpacity = opacity
        nsView.applyBrowserChrome()
    }

    static func dismantleNSView(
        _ nsView: BrowserNativeWindowControlsHostView,
        coordinator: Void
    ) {
        nsView.restoreWindowChrome()
    }
}
