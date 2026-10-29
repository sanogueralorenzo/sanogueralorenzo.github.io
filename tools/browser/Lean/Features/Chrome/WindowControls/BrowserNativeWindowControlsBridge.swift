import SwiftUI

/// Follows the sidebar's animation while keeping its closing edge immediate.
struct BrowserWindowControlsPresentation: @MainActor AnimatableModifier {
    let showsSidebar: Bool
    private var sidebarReveal: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(showsSidebar: Bool) {
        self.showsSidebar = showsSidebar
        sidebarReveal = showsSidebar ? 1 : 0
    }

    var animatableData: CGFloat {
        get { sidebarReveal }
        set { sidebarReveal = newValue }
    }

    func body(content: Content) -> some View {
        content.background(BrowserNativeWindowControlsBridge(
            isVisible: showsSidebar && sidebarReveal >= 1,
            animatesReveal: !reduceMotion))
    }
}

struct BrowserNativeWindowControlsBridge: NSViewRepresentable {
    let isVisible: Bool
    let animatesReveal: Bool

    func makeNSView(context: Context) -> BrowserNativeWindowControlsHostView {
        let view = BrowserNativeWindowControlsHostView()
        view.animatesReveal = animatesReveal
        view.isVisible = isVisible
        return view
    }

    func updateNSView(
        _ nsView: BrowserNativeWindowControlsHostView,
        context: Context
    ) {
        nsView.animatesReveal = animatesReveal
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
