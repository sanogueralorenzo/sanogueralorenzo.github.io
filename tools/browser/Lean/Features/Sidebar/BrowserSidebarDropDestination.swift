import AppKit
import SwiftUI

/// Internal moves belong to the browser, including over native WebKit views.
/// Outside a browser lift this surface does not participate in hit testing.
struct BrowserSidebarDropDestination: NSViewRepresentable {
    let store: BrowserStore

    func makeNSView(context: Context) -> BrowserSidebarDropDestinationView {
        BrowserSidebarDropDestinationView(store: store)
    }
    func updateNSView(_ view: BrowserSidebarDropDestinationView, context: Context) {}
}

@MainActor
final class BrowserSidebarDropDestinationView: NSView {
    private weak var store: BrowserStore?

    init(store: BrowserStore) {
        self.store = store
        super.init(frame: .zero)
        registerForDraggedTypes([.init(BrowserDragPayload.type)])
    }
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard store?.owner.sidebarDrag != nil, bounds.contains(convert(point, from: superview)) else { return nil }
        return self
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { resolve(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { resolve(sender) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !resolve(sender).isEmpty }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard !resolve(sender).isEmpty, let store else { return false }
        let accepted = withAnimation(
            LeanMotion.collection.unlessReducingMotion(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        ) {
            store.commitSidebarDrop()
        }
        if accepted {
            window?.makeKeyAndOrderFront(nil)
            store.owner.activeWindowID = store.id
            store.runtimeRevision &+= 1
        }
        return accepted
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        guard let store else { return }
        store.sidebarReorder.move(to: NSPoint(x: -1_000_000, y: -1_000_000), in: store)
    }

    private func resolve(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let store, !store.isClosed, !store.owner.sidebarDropCommitted,
            store.owner.sidebarDrag != nil, let window
        else { return [] }
        let point = window.convertPoint(toScreen: sender.draggingLocation)
        store.sidebarReorder.move(to: point, in: store)
        store.owner.sidebarDragSource?.updatePreview(to: point, in: store)
        return store.canCommitSidebarDrop ? .move : []
    }
}
