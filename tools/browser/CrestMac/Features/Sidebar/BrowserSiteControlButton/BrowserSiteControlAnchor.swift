import SwiftUI

/// A native view the composition places behind the Site Controls button, so an
/// engine can anchor its own popups to the control that lists its extensions.
struct BrowserSiteControlAnchor: Sendable {
    let makeView: @MainActor @Sendable () -> NSView
}

extension EnvironmentValues {
    /// Nil when the composed engine anchors nothing there.
    @Entry var browserSiteControlAnchor: BrowserSiteControlAnchor? = nil
}

struct BrowserSiteControlAnchorHost: NSViewRepresentable {
    let anchor: BrowserSiteControlAnchor

    func makeNSView(context: Context) -> NSView { anchor.makeView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
