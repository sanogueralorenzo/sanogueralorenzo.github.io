import AppKit
import SwiftUI

struct BrowserNativeSplit: NSViewRepresentable {
    let store: BrowserStore
    let pages: [BrowserPage]
    let split: BrowserSplit?
    let drop: BrowserSplitDropLayout?
    func makeNSView(context: Context) -> BrowserSplitHost { BrowserSplitHost() }
    func updateNSView(_ host: BrowserSplitHost, context: Context) {
        host.update(store: store, pages: pages, split: split, drop: drop)
    }
    static func dismantleNSView(_ host: BrowserSplitHost, coordinator: ()) { host.disconnect() }
}

@MainActor final class BrowserSplitHost: NSSplitView, NSSplitViewDelegate {
    private enum Slot: Equatable {
        case page(UUID)
        case gap(UUID)
    }
    private var slots: [Slot] = []
    private var slotFrames: [NSView: CGRect]?
    private var panes: [UUID: NSHostingView<BrowserPageContent>] = [:]
    private var placeholders: [UUID: NSHostingView<BrowserSplitDropCard>] = [:]
    private var fractions: [Double] = []
    private var applying = false
    private var draggingDivider = false
    private var identity: UUID?
    private var dropping = false
    private let geometryID = UUID()
    private weak var store: BrowserStore?
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        delegate = self
        arrangesAllSubviews = false
        dividerStyle = .thin
    }
    required init?(coder: NSCoder) { nil }
    func update(store: BrowserStore, pages: [BrowserPage], split: BrowserSplit?, drop: BrowserSplitDropLayout?) {
        self.store = store
        identity = split?.id
        dropping = drop != nil
        let lifted = Set(drop?.incoming ?? [])
        let nextSlots = (drop?.orderedIDs ?? pages.map(\.id)).map { lifted.contains($0) ? Slot.gap($0) : .page($0) }
        if !slots.isEmpty, slots != nextSlots, window != nil {
            slotFrames = Dictionary(uniqueKeysWithValues: arrangedSubviews.map { ($0, $0.frame) })
        }
        slots = nextSlots
        applying = true
        let horizontal = split?.direction != .vertical
        if isVertical != horizontal { isVertical = horizontal }
        for (id, view) in panes where !pages.contains(where: { $0.id == id }) {
            unarrange(view)
            view.removeFromSuperview()
            panes[id] = nil
        }
        for page in pages {
            let view = panes[page.id] ?? NSHostingView(rootView: BrowserPageContent(page: page, store: store))
            view.sizingOptions = []
            view.rootView = BrowserPageContent(page: page, store: store)
            panes[page.id] = view
        }
        for (id, view) in placeholders where !lifted.contains(id) {
            unarrange(view)
            view.removeFromSuperview()
            placeholders[id] = nil
        }
        for (id, view) in panes {
            let hidden = lifted.contains(id)
            if hidden {
                unarrange(view)
                view.frame = .zero
            }
            view.isHidden = hidden
        }
        for (index, id) in (drop?.orderedIDs ?? pages.map(\.id)).enumerated() {
            let view: NSView
            if lifted.contains(id) {
                let placeholder =
                    placeholders[id]
                    ?? NSHostingView(
                        rootView: BrowserSplitDropCard(
                            tab: store.activeSpace.tabs.first { $0.id == id }))
                placeholder.sizingOptions = []
                placeholders[id] = placeholder
                view = placeholder
            } else if let pane = panes[id] {
                view = pane
            } else {
                continue
            }
            if arrangedSubviews.firstIndex(of: view) != index {
                unarrange(view)
                insertArrangedSubview(view, at: min(index, arrangedSubviews.count))
            }
        }
        fractions = drop?.projectedFractions ?? split?.fractions ?? pages.map { _ in 1 / Double(max(1, pages.count)) }
        applying = false
        needsLayout = true
    }
    private func unarrange(_ view: NSView) {
        // NSSplitView removes its KVO registrations here even for a nonmember.
        // A lifted host stays mounted and can receive several updates.
        if arrangedSubviews.contains(view) { removeArrangedSubview(view) }
    }
    override func layout() {
        applying = true
        super.layout()
        applying = false
        if !draggingDivider { applyLayout() }
        measureCards()
    }
    private func applyLayout() {
        guard !applying, arrangedSubviews.count == fractions.count else { return }
        applying = true
        defer { applying = false }
        let frames = BrowserSplitDropLayout.frames(
            fractions: fractions, in: bounds, vertical: !isVertical, divider: dividerThickness)
        let previous = slotFrames
        slotFrames = nil
        let animate = previous != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for (view, frame) in zip(arrangedSubviews, frames) {
            if animate {
                view.frame =
                    previous?[view]
                    ?? (isVertical
                        ? CGRect(x: frame.midX, y: frame.minY, width: 0, height: frame.height)
                        : CGRect(x: frame.minX, y: frame.midY, width: frame.width, height: 0))
            }
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animate ? 0.22 : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for (view, frame) in zip(arrangedSubviews, frames) {
                if animate { view.animator().frame = frame } else { view.frame = frame }
            }
        }
    }
    override func mouseDown(with event: NSEvent) {
        draggingDivider = true
        super.mouseDown(with: event)
        splitViewDidResizeSubviews(Notification(name: NSSplitView.didResizeSubviewsNotification, object: self))
        draggingDivider = false
    }
    func splitView(
        _ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect, forDrawnRect drawnRect: NSRect,
        ofDividerAt dividerIndex: Int
    ) -> NSRect {
        drawnRect.insetBy(dx: isVertical ? -4 : 0, dy: isVertical ? 0 : -4)
    }
    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard !applying, draggingDivider, !dropping, let identity else { return }
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

    private func measureCards() {
        guard let store, let window, let content = window.contentView else { return }
        func global(_ view: NSView) -> CGRect { content.convert(view.convert(view.bounds, to: nil), from: nil) }
        let frames = panes.filter { !$0.value.isHidden }.mapValues(global)
        let gap = placeholders.values.map(global).reduce(CGRect.null) { $0.union($1) }
        store.sidebarReorder.registerContent(
            owner: geometryID, spaceID: store.activeSpace.id, shown: store.selectedTab?.id,
            bounds: global(self), cards: frames, gap: gap.isNull ? nil : gap,
            divider: dividerThickness)
    }

    func disconnect() { store?.sidebarReorder.removeContent(owner: geometryID) }
}

private struct BrowserSplitDropCard: View {
    let tab: BrowserTab?
    var body: some View {
        RoundedRectangle(cornerRadius: 13).fill(.primary.opacity(0.035))
            .overlay(alignment: .topLeading) {
                if let tab {
                    HStack(spacing: 9) {
                        TabIcon(tab: tab)
                        Text(tab.customTitle ?? tab.title).lineLimit(1)
                    }
                    .font(.system(size: 13)).padding(16)
                }
            }
            .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(LeanBrandTheme.line, lineWidth: 1) }
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}
