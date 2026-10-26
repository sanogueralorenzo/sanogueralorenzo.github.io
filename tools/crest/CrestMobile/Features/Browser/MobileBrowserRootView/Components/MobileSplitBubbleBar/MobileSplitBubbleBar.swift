import SwiftUI

/// The address bar inside a Split View: the bar stands for the card on show,
/// and a favicon bubble either side stands for the next card that way, in the
/// bar's own glass. Cards further out stack behind those bubbles, each in its
/// own glass so the stack never runs together.
///
/// Every card has a place relative to the shown one, and the address bar's
/// swipe slides every place along with the page. So as a swipe heads for a
/// card, that card's bubble merges into the bar while the card it leaves pops
/// out of the bar's other side; a swipe that leaves the split through an end
/// gathers every bubble into the bar. Outside a split the bar stands alone.
struct MobileSplitBubbleBar<Bar: View>: View {
    // MARK: - Static Variables

    /// The deepest stack whose cards still peek out; deeper ones hide.
    static var deepestPeek: CGFloat { 2 }
    /// How close a merging bubble comes before its glass flows into the bar's.
    static var mergeSpacing: CGFloat { 16 }

    // MARK: - Variables

    /// The cards the window shows side by side, in order, or one tab alone.
    let cards: [TabStateModel]
    let shownTabID: UUID?
    let swipe: MobileTabSwipe
    let favicons: FaviconAssets
    let profileID: UUID?
    /// Moves one card toward a bubble, as a swipe would.
    let step: (AdjacentDirection) -> Void
    @ViewBuilder let bar: Bar

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How far the bubbles still have to come out of the bar after the window
    /// arrived in a split from a tab alone, from 1 to 0.
    @State private var arriving: CGFloat = 0

    // MARK: - Actions - Presentation

    /// One layout whether or not a split is on show, so the bar keeps its
    /// identity as the window moves in and out of one.
    var body: some View {
        let shown = isSplit ? shownIndex : nil
        let focus = shown.map(focus(from:)) ?? 0
        let gathering = shown == nil ? 1 : gathering()
        let places = shown == nil ? [] : cards.indices.map { (CGFloat($0) - focus) * (1 - gathering) }
        let leadingSlot = slot(reaching: focus, gathering: gathering)
        let trailingSlot = slot(reaching: CGFloat(cards.count - 1) - focus, gathering: gathering)
        GlassEffectContainer(spacing: Self.mergeSpacing) {
            HStack(spacing: 0) {
                Color.clear.frame(width: leadingSlot, height: 0)
                bar
                    .overlay(alignment: .leading) {
                        bubbles(places, merging: true, side: -1, slot: 0)
                    }
                    .overlay(alignment: .trailing) {
                        bubbles(places, merging: true, side: 1, slot: 0)
                    }
                Color.clear.frame(width: trailingSlot, height: 0)
            }
        }
        .background(alignment: .leading) {
            bubbles(places, merging: false, side: -1, slot: leadingSlot)
        }
        .background(alignment: .trailing) {
            bubbles(places, merging: false, side: 1, slot: trailingSlot)
        }
        .onChange(of: isSplit) { _, isSplit in
            // Arriving in a split, its bubbles pop out of the bar.
            guard isSplit, !reduceMotion else { return }
            arriving = 1
            withAnimation(CrestMotion.spaceSwipe) { arriving = 0 }
        }
    }

    /// The bubbles on one side, `side` -1 for leading and 1 for trailing: those
    /// within a step of the bar when `merging`, which share its glass, else the
    /// ones resting or stacked further out, each in glass of its own. They are
    /// placed from an edge `slot` points out from the bar's own.
    private func bubbles(_ places: [CGFloat], merging: Bool, side: CGFloat, slot: CGFloat) -> some View {
        ZStack {
            ForEach(Array(zip(cards, places)), id: \.0.id) { card, place in
                let distance = abs(place)
                if place * side > 0, (distance < 1) == merging, distance <= Self.deepestPeek + 1 {
                    let bubble = MobileSplitBubble(
                        card: card, favicons: favicons, profileID: profileID, distance: distance,
                        isNearest: distance <= 1, show: { step(side > 0 ? .next : .previous) })
                    Group {
                        if merging {
                            bubble
                        } else {
                            GlassEffectContainer(spacing: 0) { bubble }
                        }
                    }
                    .offset(x: side * (bubble.reach - slot))
                    .zIndex(-Double(distance))
                }
            }
        }
    }

    // MARK: - Mutators

    private var isSplit: Bool {
        cards.count >= SplitGroupState.minimumShownMembers
    }

    private var shownIndex: Int? {
        cards.firstIndex { $0.id == shownTabID }
    }

    /// Where the swipe has moved the bar among the cards, as a fractional
    /// card index: the shown card's, plus the swipe's travel while it heads
    /// for another card of the split.
    private func focus(from shown: Int) -> CGFloat {
        guard let target = swipeTarget, cards.contains(where: { $0.id == target }) else {
            return CGFloat(shown)
        }
        return CGFloat(shown) + swipe.travel
    }

    /// How far a swipe has carried the bar out of the split through an end,
    /// or how far the bubbles have yet to come out on arriving in it, from 0
    /// to 1, which gathers every bubble into the bar.
    private func gathering() -> CGFloat {
        guard let target = swipeTarget, !cards.contains(where: { $0.id == target }) else { return arriving }
        return max(arriving, min(1, abs(swipe.travel)))
    }

    /// The tab the swipe is heading for, if it is moving toward one.
    private var swipeTarget: UUID? {
        if swipe.travel > 0 { return swipe.neighbors.nextTabID }
        if swipe.travel < 0 { return swipe.neighbors.previousTabID }
        return nil
    }

    /// The room one side keeps beside the bar for `cards` cards that way: a
    /// bubble's once there is one, growing to it as the first slides out, and
    /// the stack's peeks beyond it.
    private func slot(reaching cards: CGFloat, gathering: CGFloat) -> CGFloat {
        let bubble = (MobileSplitBubble.diameter + MobileSplitBubble.gap) * min(1, max(0, cards))
        let stack = MobileSplitBubble.stackPeek * min(Self.deepestPeek, max(0, cards - 1))
        return (bubble + stack) * (1 - gathering)
    }
}
