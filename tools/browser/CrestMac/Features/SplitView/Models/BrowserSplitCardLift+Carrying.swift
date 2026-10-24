import SwiftUI

/// The whole of "Fancy Move": when a Split View card can be picked up, which
/// slot the gap it leaves is standing in, and how the row is drawn while
/// somebody is carrying one.
///
/// Every decision is arithmetic over frames and booleans, for the same reason
/// the surface's focus guards are: the gesture itself is a local `NSEvent`
/// monitor no unit test can drive, so what *is* testable has to be the answers
/// it asks for rather than the asking.
extension BrowserSplitCardLift {
    // MARK: - Static Variables

    /// The modifiers that turn a press into a carry: the same pair that moves a
    /// card by keyboard.
    ///
    /// ⇧⌘← and ⇧⌘→ already mean "move this card one place"; ⇧⌘ and the pointer
    /// means "move this card to wherever I put it". One idea, one binding,
    /// reached two ways.
    static let carryModifiers: BrowserKeyboardModifierFlags = [.command, .shift]

    // MARK: - Actions - Carrying

    /// Whether a modified mouse-down lifts the card it landed in.
    ///
    /// The guards, in the order they read:
    ///
    /// - **⇧⌘, and nothing else.** The bare click is how focus moves between
    ///   cards, and how web content receives every click somebody makes;
    ///   reordering has to ask for itself. The match is exact rather than a
    ///   containment test, so ⌥⇧⌘ and ⌃⇧⌘ stay available to the page and to
    ///   whatever else may want them.
    /// - **Inside a card.** The insets around the row, and the row's own gaps,
    ///   are not cards.
    /// - **Not a divider.** The handles overhang the cards they separate, so a
    ///   point a few units inside a card's edge is both inside that card and
    ///   under the control that resizes it. The resize wins: it is the older
    ///   affordance and the one already under the pointer's own cursor.
    /// - **More than one card.** A lone card has nowhere to go.
    /// - **No sidebar drag, no command palette.** Both already own the pointer,
    ///   exactly as they do for click-to-focus.
    ///
    /// Focus is deliberately absent from this list, and the omission is the
    /// point: the card somebody is pointing at is the card they may pick up,
    /// whether or not the chrome is currently speaking for it. Nothing here can
    /// tell the focused card apart from any other.
    static func picksUp(
        modifiers: BrowserKeyboardModifierFlags,
        isInsideCard: Bool,
        isOverDivider: Bool,
        memberCount: Int,
        isDraggingSidebarItem: Bool,
        isCommandPalettePresented: Bool
    ) -> Bool {
        modifiers == carryModifiers
            && isInsideCard
            && !isOverDivider
            && memberCount > 1
            && !isDraggingSidebarItem
            && !isCommandPalettePresented
    }

    /// The card `point` landed in, resolved against the row's own membership.
    ///
    /// The registry is keyed by tab and outlives the cards in it: a member the
    /// row is animating out keeps its frame until SwiftUI runs its
    /// disappearance, and a frame left behind by a card that has gone overlaps
    /// the cards that closed up around it. A lookup over the registry alone
    /// therefore has two ways to answer wrongly — with a tab that is no longer a
    /// member, or with whichever of two overlapping frames a dictionary happened
    /// to visit first — and a pickup that resolved a stranger simply refused,
    /// silently, leaving the press to be an ordinary click.
    ///
    /// Asking the members first removes both. Membership is the row's order, the
    /// answer carries the slot as well as the tab, and a frame belonging to
    /// nobody on show is not a card anybody can be pointing at.
    static func card<Member: Identifiable>(
        at point: CGPoint,
        members: [Member],
        cardFrames: [UUID: CGRect]
    ) -> (tabID: UUID, index: Int, frame: CGRect)? where Member.ID == UUID {
        for (index, member) in members.enumerated() {
            guard let frame = cardFrames[member.id],
                !frame.isEmpty,
                frame.contains(point)
            else { continue }
            return (member.id, index, frame)
        }
        return nil
    }

    /// The cards on show, in reading order — the only frames a divider between
    /// two of them may be measured from.
    ///
    /// Restricted to members for the same reason `card(at:members:cardFrames:)`
    /// is: a frame left behind by a departing card sits between two that are
    /// still there, and the midpoint between it and its neighbour lands in the
    /// middle of a card, which would read a whole column as a resize divider and
    /// refuse every pickup inside it.
    static func orderedMemberFrames<Member: Identifiable>(
        members: [Member],
        cardFrames: [UUID: CGRect]
    ) -> [CGRect] where Member.ID == UUID {
        BrowserSplitColumnLayout.orderedCardFrames(members.compactMap { cardFrames[$0.id] })
    }

    /// Whether `point` belongs to the divider between two cards rather than to
    /// the card whose frame contains it.
    ///
    /// Measured from the cards themselves rather than from a handle's frame, for
    /// the same reason a divider drag is: the handles are positioned from the
    /// widths the row is drawing, so the cards are the only geometry that is
    /// true before the handle has been laid out.
    static func isOverDivider(
        _ point: CGPoint,
        orderedCardFrames: [CGRect],
        panelFrame: CGRect? = nil,
        hitWidth: CGFloat = BrowserSplitLayoutMetrics.resizeHandleHitWidth
    ) -> Bool {
        let reach = max(0, hitWidth) / 2
        let frames = BrowserSplitColumnLayout.orderedCardFrames(
            orderedCardFrames + (panelFrame.map { [$0] } ?? [])
        )
        return zip(frames, frames.dropFirst()).contains {
            leading, trailing in
            abs(point.x - (leading.maxX + trailing.minX) / 2) <= reach
        }
    }

    /// The slot the carried card would drop into, from where the pointer is and
    /// where the cards it is *not* carrying are.
    ///
    /// The lifted card's own column is the gap, and a gap the pointer is inside
    /// is not a card it has passed, so the card is excluded before the same
    /// arithmetic a drag from the sidebar uses runs over what is left. The
    /// remaining `n - 1` neighbours answer in `0...n - 1`, which is exactly the
    /// vocabulary `moveSplitMember(toMemberIndex:)` takes — remove the card, put
    /// it back at this index — so the index the gap is drawn at is the index the
    /// release commits, with no translation in between.
    ///
    /// The answer survives the layout it causes, the way the drop placeholder's
    /// does: moving the gap toward the pointer moves the neighbour it passed the
    /// other way, which is the direction that holds the new index rather than
    /// arguing with it.
    ///
    /// Frames are screen geometry and member order is reading order, and the two
    /// only agree left to right. A mirrored row draws the first member at the
    /// trailing edge, so the count of cards the pointer has passed is counted
    /// from the wrong end and is reflected back before it leaves.
    static func gapIndex(
        at point: CGPoint,
        cardFrames: [UUID: CGRect],
        lifted liftedTabID: UUID,
        layoutDirection: LayoutDirection
    ) -> Int {
        let neighbours = BrowserSplitColumnLayout.orderedCardFrames(
            cardFrames.lazy.filter { $0.key != liftedTabID }.map(\.value)
        )
        let passed = BrowserSplitColumnLayout.insertionIndex(
            at: point,
            orderedCardFrames: neighbours
        )
        guard layoutDirection == .rightToLeft else { return passed }
        return neighbours.count - passed
    }

    /// The row as it is drawn while one card is being carried: the lifted member
    /// moved to the gap, everybody else closed up around where it was.
    ///
    /// The lifted member stays in the list rather than standing down for a slot
    /// of its own, and that is the whole reason a lift never remounts a card.
    /// Its `UUID` is still the identity at the gap's position, so `ForEach`
    /// moves the host it already has instead of building a second one for a live
    /// `WKWebView` to be handed to. The card simply stops drawing while it is
    /// away.
    ///
    /// It is also why the drop is invisible: the row is already in the order the
    /// commit produces, so the session catching up changes nothing on screen.
    static func displayMembers<Member: Identifiable>(
        _ members: [Member],
        lifted liftedTabID: UUID?,
        gapIndex: Int
    ) -> [Member] where Member.ID == UUID {
        guard let liftedTabID,
            let sourceIndex = members.firstIndex(where: { $0.id == liftedTabID })
        else { return members }
        var ordered = members
        let lifted = ordered.remove(at: sourceIndex)
        ordered.insert(lifted, at: min(max(gapIndex, 0), ordered.count))
        return ordered
    }

    /// Where inside the card the pointer took hold, as a fraction of it on each
    /// axis.
    ///
    /// The preview is scaled about this point rather than about its centre, so
    /// the pixel somebody grabbed stays under the cursor for the whole carry
    /// however far the card rises.
    static func grabFraction(pointer: CGPoint, in cardFrame: CGRect) -> CGPoint {
        CGPoint(
            x: fraction(pointer.x - cardFrame.minX, of: cardFrame.width),
            y: fraction(pointer.y - cardFrame.minY, of: cardFrame.height)
        )
    }

    /// A degenerate card is grabbed in the middle, which is the one answer that
    /// cannot put the preview somewhere absurd.
    private static func fraction(
        _ distance: CGFloat,
        of extent: CGFloat
    ) -> CGFloat {
        guard extent > 0, distance.isFinite else { return 0.5 }
        return min(max(distance / extent, 0), 1)
    }
}
