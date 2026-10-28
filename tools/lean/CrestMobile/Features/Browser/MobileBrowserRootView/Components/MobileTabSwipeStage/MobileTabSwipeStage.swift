import SwiftUI

// MARK: - Types

/// One page of the address bar's swipe stage.
struct MobileTabSwipeStageSlot: Identifiable, Equatable {
    /// The slot's identity: its tab while it shows a live page, else the
    /// shown slot's own, so the shown tab's other surfaces keep theirs.
    let id: UUID
    /// The tab the slot shows, or nil for the shown slot of a window showing
    /// no tab.
    let tabID: UUID?
    /// How many tabs on from the shown one the slot sits: 0 for the shown tab,
    /// 1 for the next and -1 for the previous.
    let place: Int
}

/// The page area under the address bar's swipe: the shown tab where the swipe
/// has moved it, and beside it the tabs either side, sliding in the way the
/// next Space's page slides in.
///
/// Each page is one slot, keyed by its tab while it shows a live page, so a
/// page that slides in keeps its web view's host as it becomes the shown tab
/// and never lays out anew. When the swipe lands, the core shows the tab it
/// went to in the same update that puts the stage back at rest. The
/// neighbours take no touches, and while nothing moves only pages ready to
/// slide in wait beside the shown one, out of sight.
struct MobileTabSwipeStage<Page: View>: View {
    // MARK: - Static Variables

    /// The shown slot's identity while it shows no live page: the nil UUID,
    /// which no tab has.
    private static var restingID: UUID { UUID(uuid: uuid_t(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) }

    // MARK: - Variables

    let swipe: MobileTabSwipe
    let shownTabID: UUID?
    /// The shown tab while it shows a live page, which keys its slot.
    let shownLiveTabID: UUID?
    /// Draws a slot. A tab draws the same view whichever place it holds.
    @ViewBuilder let page: (_ slot: MobileTabSwipeStageSlot, _ isMoving: Bool) -> Page

    // MARK: - Actions - Presentation

    var body: some View {
        let isMoving = swipe.phase != .idle
        ZStack {
            ForEach(slots) { slot in
                page(slot, isMoving)
                    .modifier(MobileTabSwipeSlot(swipe: swipe, place: CGFloat(slot.place)))
                    .allowsHitTesting(slot.place == 0)
                    .accessibilityHidden(slot.place != 0)
                    .zIndex(slot.place == 0 ? 1 : 0)
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            swipe.pageWidth = width
        }
    }

    /// The shown tab's slot and the slots either side of it, each tab once.
    private var slots: [MobileTabSwipeStageSlot] {
        let shown = MobileTabSwipeStageSlot(id: shownLiveTabID ?? Self.restingID, tabID: shownTabID, place: 0)
        let neighbors = [(swipe.neighbors.previousTabID, -1), (swipe.neighbors.nextTabID, 1)]
            .compactMap { tabID, place in tabID.map { MobileTabSwipeStageSlot(id: $0, tabID: $0, place: place) } }
            .filter { $0.id != shown.id && $0.tabID != shownTabID }
        return [shown] + neighbors
    }
}
