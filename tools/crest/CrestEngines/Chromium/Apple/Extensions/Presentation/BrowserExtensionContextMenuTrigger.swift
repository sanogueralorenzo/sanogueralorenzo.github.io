import AppKit
import SwiftUI

/// Bridges a secondary click on a SwiftUI extension button into a screen-space
/// anchor, mirroring how `BrowserExtensionPopupAnchorReader` reports a popup
/// anchor for the same controls.
struct BrowserExtensionContextMenuTrigger: NSViewRepresentable {
    let presentMenu: (BrowserExtensionPopupAnchor?) -> Void

    func makeNSView(
        context: Context
    ) -> BrowserExtensionContextMenuTriggerView {
        let view = BrowserExtensionContextMenuTriggerView()
        attach(to: view)
        return view
    }

    func updateNSView(
        _ nsView: BrowserExtensionContextMenuTriggerView,
        context: Context
    ) {
        attach(to: nsView)
    }

    private func attach(to view: BrowserExtensionContextMenuTriggerView) {
        let presentMenu = presentMenu
        view.presentMenu = { [weak view] event in
            guard let window = view?.window else {
                presentMenu(nil)
                return
            }
            presentMenu(
                BrowserExtensionPopupAnchor(
                    screenPoint: window.convertPoint(
                        toScreen: event.locationInWindow
                    ),
                    sourceWindow: window
                )
            )
        }
    }
}
