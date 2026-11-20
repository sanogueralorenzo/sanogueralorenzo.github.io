import AppKit
import SwiftUI

/// Track internal identity outside the provider because SwiftUI can filter its representations.
struct BrowserSidebarDragSource: ViewModifier {
    let store: BrowserStore
    let payload: () -> BrowserDragPayload
    let title: String
    var url: URL?
    var isEnabled = true
    @State private var source = BrowserSidebarDragSourceView()

    func body(content: Content) -> some View {
        content
            .background(BrowserSidebarDragSourceHost(view: source).accessibilityHidden(true))
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { _ in
                        guard isEnabled else { return }
                        source.begin(store: store, payload: payload(), title: title, url: url)
                    })
    }
}

private struct BrowserSidebarDragSourceHost: NSViewRepresentable {
    let view: BrowserSidebarDragSourceView
    func makeNSView(context: Context) -> BrowserSidebarDragSourceView { view }
    func updateNSView(_ view: BrowserSidebarDragSourceView, context: Context) {}
}

@MainActor
final class BrowserSidebarDragSourceView: NSView, NSDraggingSource {
    private weak var owner: BrowserSessionOwner?
    private var exportsURL = false
    private var preview: BrowserSidebarDragPreview?

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func begin(store: BrowserStore, payload: BrowserDragPayload, title: String, url: URL?) {
        guard window != nil, store.owner.sidebarDrag.payload == nil,
            let event = NSApp.currentEvent, event.type == .leftMouseDragged, event.window === window
        else { return }
        let item = NSPasteboardItem()
        // Export only the marker and optional URL. Internal IDs stay in the process.
        item.setData(Data(), forType: .init(BrowserDragPayload.type))
        if let url {
            item.setString(url.absoluteString, forType: .URL)
            if url.isFileURL { item.setString(url.absoluteString, forType: .fileURL) }
        }
        let dragging = NSDraggingItem(pasteboardWriter: item)
        // Use a transparent AppKit preview because the child panel draws the visible one.
        let transparent = NSImage(size: NSSize(width: 1, height: 1), flipped: false) { _ in true }
        dragging.setDraggingFrame(bounds, contents: transparent)
        owner = store.owner
        exportsURL = url != nil
        guard store.owner.sidebarDrag.begin(payload, from: self, in: store) else { return }
        if let window {
            let frame: CGRect
            if let id = store.owner.sidebarDrag.lift?.anchorID, let measured = store.sidebarReorder.frame(of: id),
                let content = window.contentView
            {
                frame = window.convertToScreen(content.convert(measured, to: nil))
            } else {
                frame = window.convertToScreen(convert(bounds, to: nil))
            }
            let pointer = NSEvent.mouseLocation
            preview = BrowserSidebarDragPreview(
                store: store, payload: payload, title: title, frame: frame,
                grab: CGPoint(x: pointer.x - frame.minX, y: frame.maxY - pointer.y))
            preview?.move(to: NSEvent.mouseLocation, target: nil, frame: nil)
        }
        store.isDragging = true
        let session = beginDraggingSession(with: [dragging], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        guard let owner else { return }
        let contexts = owner.contexts.values.filter { !$0.isClosed }
        let window = NSApp.orderedWindows.first { window in
            window.frame.contains(screenPoint) && contexts.contains { $0.window === window }
        }
        var destination: BrowserStore?
        for context in contexts {
            if context.sidebarReorder.lift == nil, let lift = owner.sidebarDrag.lift {
                context.sidebarReorder.begin(lift, in: context)
            }
            let local = context.window.map { $0.convertPoint(fromScreen: screenPoint) } ?? .zero
            let edge = context.showsSidebar ? context.sidebarDropBoundary : SidebarGeometry.revealWidth
            context.isDragging = context.window === window && local.x <= edge
            if !context.sidebarDocked {
                if !context.isDragging {
                    context.sidebarRevealed = false
                } else if local.x <= SidebarGeometry.revealWidth {
                    context.sidebarRevealed = true
                }
            }
            if context.window === window {
                context.sidebarReorder.move(to: screenPoint, in: context)
                destination = context
            } else {
                context.sidebarReorder.move(to: NSPoint(x: -1_000_000, y: -1_000_000), in: context)
            }
        }
        if let destination {
            updatePreview(to: screenPoint, in: destination)
        } else {
            preview?.move(to: screenPoint, target: nil, frame: nil)
        }
    }

    func updatePreview(to point: NSPoint, in store: BrowserStore) {
        preview?.move(
            to: point, target: store.sidebarReorder.target, frame: store.sidebarReorder.previewFrame(in: store))
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext)
        -> NSDragOperation
    {
        context == .withinApplication ? .move : exportsURL ? .copy : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if let owner { owner.sidebarDrag.finish(accepted: !operation.isEmpty, preview: preview, in: owner) }
        preview = nil
        owner = nil
        exportsURL = false
    }
}
