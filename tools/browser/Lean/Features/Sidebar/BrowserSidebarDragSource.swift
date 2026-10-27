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
    private var exportsURL = false

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
        let count = payload.ids.count + payload.folderIDs.count
        let space = store.session.spaces.first { $0.id == payload.spaceID }
        let folder = payload.ids.isEmpty ? space?.folders.first { payload.folderIDs.contains($0.id) } : nil
        let tab = space?.tabs.first { payload.ids.contains($0.id) }
        let preview = HStack(spacing: 8) {
            if let tab {
                TabIcon(tab: tab)
            } else {
                Image(systemName: folder != nil ? "folder.fill" : "circle.fill")
            }
            Text(folder?.title ?? title).lineLimit(1)
            if count > 1 { Text("\(count)").foregroundStyle(.secondary) }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .frame(width: max(80, bounds.width), height: max(28, bounds.height), alignment: .leading)
        .background(LeanBrandTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        .environment(
            \.colorScheme,
            window?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light)
        let renderer = ImageRenderer(content: preview)
        renderer.scale = window?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return }
        dragging.setDraggingFrame(bounds, contents: image)
        owner = store.owner
        exportsURL = url != nil
        store.owner.sidebarDrag = payload
        store.owner.sidebarDragSource = self
        store.isDragging = true
        let session = beginDraggingSession(with: [dragging], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext)
        -> NSDragOperation
    {
        context == .withinApplication ? .move : exportsURL ? .copy : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        owner?.sidebarDrag = nil
        owner?.sidebarDragSource = nil
        if let owner {
            for context in owner.contexts.values { context.isDragging = false }
        }
        owner = nil
        exportsURL = false
    }
}
