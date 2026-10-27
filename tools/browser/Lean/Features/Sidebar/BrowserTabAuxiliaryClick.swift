import AppKit
import SwiftUI

struct BrowserTabAuxiliaryClick: NSViewRepresentable {
    let store: BrowserStore
    let tabID: UUID
    func makeNSView(context: Context) -> TabAuxiliaryClickView { TabAuxiliaryClickView() }
    func updateNSView(_ view: TabAuxiliaryClickView, context: Context) {
        view.close = { store.requestCloseTab(tabID) }
    }
}

@MainActor final class TabAuxiliaryClickView: NSView {
    var close: (() -> Void)?
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard NSApp.currentEvent?.type == .otherMouseDown, NSApp.currentEvent?.buttonNumber == 2,
            bounds.contains(convert(point, from: superview))
        else { return nil }
        return self
    }
    override func otherMouseDown(with event: NSEvent) { if event.buttonNumber == 2 { close?() } }
}
