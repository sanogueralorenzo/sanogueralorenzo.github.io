import AppKit
import SwiftUI

/// AppKit owns the drag lifetime; the shared session owns the items being moved.
/// Keeping those identities locally avoids treating an internal URL representation
/// as a newly opened tab, even when SwiftUI filters the provider's representations.
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
    private weak var sourceStore: BrowserStore?
    private var exportsURL = false
    private var preview: BrowserSidebarDragPreview?

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func begin(store: BrowserStore, payload: BrowserDragPayload, title: String, url: URL?) {
        guard window != nil, store.owner.sidebarDrag == nil,
            let event = NSApp.currentEvent, event.type == .leftMouseDragged, event.window === window
        else { return }
        let item = NSPasteboardItem()
        // Only the marker and optional URL leave the process. The item
        // identities, including those from private Spaces, stay with the owner.
        item.setData(Data(), forType: .init(BrowserDragPayload.type))
        if let url {
            item.setString(url.absoluteString, forType: .URL)
            if url.isFileURL { item.setString(url.absoluteString, forType: .fileURL) }
        }
        let dragging = NSDraggingItem(pasteboardWriter: item)
        // The inert child panel owns the one visible preview, including over
        // WebKit and outside the list's scroll clip.
        let transparent = NSImage(size: NSSize(width: 1, height: 1), flipped: false) { _ in true }
        dragging.setDraggingFrame(bounds, contents: transparent)
        owner = store.owner
        sourceStore = store
        exportsURL = url != nil
        store.owner.sidebarLandingToken = nil
        store.owner.sidebarLandingIDs = []
        store.owner.sidebarLandingPreview?.cancel()
        store.owner.sidebarLandingPreview = nil
        store.owner.sidebarDrag = payload
        store.owner.sidebarDragSource = self
        if payload.kind == .space {
            for context in store.owner.contexts.values where !context.isClosed {
                context.sidebarReorder.beginSpace(payload.spaceID, in: context)
            }
        }
        if let space = store.session.spaces.first(where: { $0.id == payload.spaceID }),
            let lift = store.sidebarReorder.makeLift(payload, in: space)
        {
            store.owner.sidebarLift = lift
            for context in store.owner.contexts.values where !context.isClosed {
                context.sidebarReorder.begin(lift, in: context)
            }
        }
        if let window {
            let frame = window.convertToScreen(convert(bounds, to: nil))
            preview = BrowserSidebarDragPreview(
                store: store, payload: payload, title: title, frame: frame,
                grab: convert(event.locationInWindow, from: nil))
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
            if context.sidebarReorder.lift == nil, let lift = owner.sidebarLift {
                context.sidebarReorder.begin(lift, in: context)
            }
            context.isDragging = context === sourceStore || context.window === window
            if context.window === window {
                context.sidebarReorder.move(to: screenPoint, in: context)
                destination = context
            } else {
                context.sidebarReorder.move(to: NSPoint(x: -1_000_000, y: -1_000_000), in: context)
            }
        }
        preview?.move(
            to: screenPoint, target: destination?.sidebarReorder.target,
            frame: destination.flatMap { $0.sidebarReorder.landingFrame(in: $0) })
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext)
        -> NSDragOperation
    {
        context == .withinApplication ? .move : exportsURL ? .copy : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        // AppKit can deliver the source button's release after the drop.
        // Crest suppresses activation for the same quarter-second handoff.
        owner?.sidebarActivationSuppressedUntil = Date().addingTimeInterval(0.25)
        if let owner {
            let token = UUID()
            owner.sidebarLandingToken = token
            if let lift = owner.sidebarLift {
                owner.sidebarLandingIDs = lift.rootIDs
            } else if let payload = owner.sidebarDrag, payload.kind == .space {
                owner.sidebarLandingIDs = [payload.spaceID]
            } else {
                owner.sidebarLandingIDs = []
            }
            let landing = owner.contexts.values.compactMap { $0.sidebarReorder.landingFrame(in: $0) }.first
            owner.sidebarDrag = nil
            owner.sidebarDragSource = nil
            owner.sidebarLift = nil
            withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : LeanMotion.dragSource) {
                for context in owner.contexts.values {
                    context.isDragging = false
                    context.sidebarReorder.finish()
                }
            }
            if let preview {
                owner.sidebarLandingPreview = preview
                preview.finish(accepted: !operation.isEmpty, landing: landing) {
                    guard owner.sidebarLandingToken == token else { return }
                    owner.sidebarLandingIDs = []
                    owner.sidebarLandingToken = nil
                    owner.sidebarLandingPreview = nil
                }
            } else {
                owner.sidebarLandingIDs = []
                owner.sidebarLandingToken = nil
            }
        }
        preview = nil
        sourceStore = nil
        owner = nil
        exportsURL = false
    }
}
