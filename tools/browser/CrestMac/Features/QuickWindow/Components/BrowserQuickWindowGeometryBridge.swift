import SwiftUI

struct BrowserQuickWindowGeometryBridge: NSViewRepresentable {
    let pagePoolRegistry: BrowserPagePoolRegistry?
    let targetWindowID: UUID?

    func makeNSView(context: Context) -> BrowserQuickWindowGeometryHostView {
        BrowserQuickWindowGeometryHostView(
            pagePoolRegistry: pagePoolRegistry,
            targetWindowID: targetWindowID
        )
    }

    func updateNSView(
        _ nsView: BrowserQuickWindowGeometryHostView,
        context: Context
    ) {
        nsView.configure(
            pagePoolRegistry: pagePoolRegistry,
            targetWindowID: targetWindowID
        )
        nsView.updateWindowGeometry()
    }
}
