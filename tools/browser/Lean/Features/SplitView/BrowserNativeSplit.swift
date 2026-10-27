import AppKit
import SwiftUI

struct BrowserNativeSplit: NSViewRepresentable {
    let store: BrowserStore
    let pages: [BrowserPage]
    let split: BrowserSplit
    func makeNSView(context: Context) -> BrowserSplitHost { BrowserSplitHost() }
    func updateNSView(_ host: BrowserSplitHost, context: Context) {
        host.update(store: store, pages: pages, split: split)
    }
}

@MainActor final class BrowserSplitHost: NSSplitView, NSSplitViewDelegate {
    private var panes: [UUID: NSHostingView<BrowserPageContent>] = [:]
    private var fractions: [Double] = []
    private var applying = false
    private var draggingDivider = false
    private var identity: UUID?
    private weak var store: BrowserStore?
    override init(frame: NSRect) {
        super.init(frame: frame)
        delegate = self
        dividerStyle = .thin
    }
    required init?(coder: NSCoder) { nil }
    func update(store: BrowserStore, pages: [BrowserPage], split: BrowserSplit) {
        self.store = store
        identity = split.id
        applying = true
        if isVertical != (split.direction == .horizontal) { isVertical = split.direction == .horizontal }
        for (id, view) in panes where !pages.contains(where: { $0.id == id }) {
            view.removeFromSuperview()
            panes[id] = nil
        }
        for (index, page) in pages.enumerated() {
            let view = panes[page.id] ?? NSHostingView(rootView: BrowserPageContent(page: page, store: store))
            view.sizingOptions = []
            view.rootView = BrowserPageContent(page: page, store: store)
            panes[page.id] = view
            if arrangedSubviews.firstIndex(of: view) != index {
                view.removeFromSuperview()
                insertArrangedSubview(view, at: index)
            }
        }
        fractions = split.fractions
        applying = false
        needsLayout = true
    }
    override func layout() {
        super.layout()
        if !draggingDivider { applyLayout() }
    }
    private func applyLayout() {
        guard !applying, arrangedSubviews.count == fractions.count else { return }
        applying = true
        defer { applying = false }
        let available = max(
            0, (isVertical ? bounds.width : bounds.height) - dividerThickness * CGFloat(max(0, fractions.count - 1)))
        var origin: CGFloat = 0
        for (index, view) in arrangedSubviews.enumerated() {
            let size = available * fractions[index]
            view.frame =
                isVertical
                ? NSRect(x: origin, y: 0, width: size, height: bounds.height)
                : NSRect(x: 0, y: origin, width: bounds.width, height: size)
            origin += size + dividerThickness
        }
    }
    override func mouseDown(with event: NSEvent) {
        draggingDivider = true
        super.mouseDown(with: event)
        draggingDivider = false
        splitViewDidResizeSubviews(Notification(name: NSSplitView.didResizeSubviewsNotification, object: self))
    }
    func splitView(
        _ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect, forDrawnRect drawnRect: NSRect,
        ofDividerAt dividerIndex: Int
    ) -> NSRect {
        drawnRect.insetBy(dx: isVertical ? -4 : 0, dy: isVertical ? 0 : -4)
    }
    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard !applying, let identity else { return }
        let sizes = arrangedSubviews.map { Double(isVertical ? $0.frame.width : $0.frame.height) }
        let total = sizes.reduce(0, +)
        guard total > 0, sizes.allSatisfy({ $0 > 0 }) else { return }
        fractions = sizes.map { $0 / total }
        store?.resizeSplit(identity, fractions: fractions)
    }
    func splitView(
        _ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        proposedMinimumPosition + 100
    }
    func splitView(
        _ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        proposedMaximumPosition - 100
    }
}
