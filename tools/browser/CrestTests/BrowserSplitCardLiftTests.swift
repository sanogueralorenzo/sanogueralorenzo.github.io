import CoreGraphics
import Foundation
import SwiftUI
import XCTest

@testable import Crest

/// "Fancy Move": when a ⇧⌘-held press picks a Split View card up, which slot
/// the gap it leaves is standing in, and how the row is drawn around it.
///
/// The gesture itself is a local `NSEvent` monitor no test can drive, which is
/// exactly why every decision it makes is a pure function. These are the
/// contract for those decisions.
final class BrowserSplitCardLiftTests: XCTestCase {

    // MARK: - Pickup

    func testAShiftCommandHeldPressInsideACardPicksItUp() {
        XCTAssertTrue(Self.picksUp())
    }

    /// The bare click is how focus moves between cards, and how web content
    /// receives every click anybody makes. Reordering asks for itself.
    func testAPressWithoutModifiersIsAnOrdinaryClick() {
        XCTAssertFalse(Self.picksUp(modifiers: []))
    }

    /// Everything the ⇧⌘ pair is not. Plain ⌘-click still opens a link in a new
    /// tab, ⌥-click still downloads, ⌃-click is still a right-click, and adding
    /// a third modifier to ⇧⌘ hands the press back to the page rather than
    /// widening the carry's claim.
    func testEveryOtherModifierCombinationIsLeftToThePage() {
        XCTAssertFalse(Self.picksUp(modifiers: .command))
        XCTAssertFalse(Self.picksUp(modifiers: .shift))
        XCTAssertFalse(Self.picksUp(modifiers: .option))
        XCTAssertFalse(Self.picksUp(modifiers: .control))
        XCTAssertFalse(Self.picksUp(modifiers: [.command, .option]))
        XCTAssertFalse(Self.picksUp(modifiers: [.command, .shift, .option]))
        XCTAssertFalse(Self.picksUp(modifiers: [.command, .shift, .control]))
    }

    /// The insets around the row, and the gaps inside it, are not cards.
    func testAPressOutsideEveryCardPicksNothingUp() {
        XCTAssertFalse(Self.picksUp(isInsideCard: false))
    }

    /// The handles overhang the cards they separate, so a press a few points
    /// inside a card's edge is both inside that card and under the control that
    /// resizes it. The resize wins.
    func testTheResizeDividerOutranksAPickup() {
        XCTAssertFalse(Self.picksUp(isOverDivider: true))
    }

    func testALoneCardHasNowhereToGo() {
        XCTAssertFalse(Self.picksUp(memberCount: 1))
    }

    /// Both already own the pointer, exactly as they do for click-to-focus.
    func testASidebarDragAndTheCommandPaletteBothRefuseAPickup() {
        XCTAssertFalse(Self.picksUp(isDraggingSidebarItem: true))
        XCTAssertFalse(Self.picksUp(isCommandPalettePresented: true))
    }

    // MARK: - Divider proximity

    // MARK: - The gap the carried card leaves

    /// The gap moves the cards it passes, and the answer has to survive that or
    /// the slot would flicker under a stationary pointer. Moving the gap toward
    /// the pointer moves the neighbour it passed the other way, which is the
    /// direction that holds the new index.
    func testTheGapSurvivesTheLayoutItsOwnMovementCauses() {
        let members = BrowserSplitCardTestFixture.members
        let widths = [CGFloat](repeating: 300, count: members.count)

        for pointerX in stride(from: CGFloat(5), to: 920, by: 5) {
            let resting = Self.registeredFrames(
                members: members,
                widths: widths
            )
            let index = Self.gapIndex(
                atX: pointerX,
                in: resting,
                lifted: Self.middle
            )
            let shifted = Self.registeredFrames(
                members: BrowserSplitCardLift.displayMembers(
                    members,
                    lifted: Self.middle,
                    gapIndex: index
                ),
                widths: widths
            )

            XCTAssertEqual(
                Self.gapIndex(atX: pointerX, in: shifted, lifted: Self.middle),
                index,
                "A pointer at \(pointerX) changed slot once the row shifted around it."
            )
        }
    }

    // MARK: - The row as it is drawn

    /// The carried member stays in the list, at its own identity, moved to the
    /// gap. That is what lets a whole reorder happen without remounting the card
    /// — and therefore without handing a live web view to a second superview.
    func testTheCarriedMemberIsMovedRatherThanReplaced() {
        let members = BrowserSplitCardTestFixture.members

        XCTAssertEqual(
            BrowserSplitCardLift.displayMembers(
                members,
                lifted: Self.middle,
                gapIndex: 0
            )
            .map(\.id),
            [Self.middle, Self.leading, Self.trailing]
        )
        XCTAssertEqual(
            BrowserSplitCardLift.displayMembers(
                members,
                lifted: Self.middle,
                gapIndex: 2
            )
            .map(\.id),
            [Self.leading, Self.trailing, Self.middle]
        )
    }

    /// A member that is no longer in the row cannot be moved within it.
    func testAnUnknownCarriedMemberChangesNothing() {
        let members = BrowserSplitCardTestFixture.members

        XCTAssertEqual(
            BrowserSplitCardLift.displayMembers(
                members,
                lifted: UUID(),
                gapIndex: 0
            ),
            members
        )
    }

    // MARK: - Which card the press landed in

    /// A frame left behind by a card the row has already closed up around
    /// overlaps the cards that took its place. Resolving through the members
    /// makes it unreachable rather than making it win a dictionary's iteration
    /// order — which is a pickup silently refused, on whichever card the
    /// stranger happened to cover.
    func testAFrameBelongingToNoMemberIsNotACard() {
        let members = Array(BrowserSplitCardTestFixture.members.prefix(2))
        var frames = Self.registeredFrames(count: 2)
        let departed = UUID()
        // The whole row, as the leaving card measured it before it shrank.
        frames[departed] = CGRect(x: 0, y: 0, width: 1_000, height: 600)

        let card = BrowserSplitCardLift.card(
            at: CGPoint(x: 150, y: 300),
            members: members,
            cardFrames: frames
        )

        XCTAssertEqual(card?.tabID, members[0].id)
        XCTAssertEqual(card?.index, 0)
    }

    /// A stranger's frame between two members would put a divider's midpoint in
    /// the middle of a card, which reads a whole column as the control that
    /// resizes it and refuses every pickup inside it.
    func testDividerGeometryIgnoresFramesNoMemberOwns() {
        let members = Array(BrowserSplitCardTestFixture.members.prefix(2))
        var frames = Self.registeredFrames(count: 2)
        frames[UUID()] = CGRect(x: 120, y: 0, width: 60, height: 600)

        let ordered = BrowserSplitCardLift.orderedMemberFrames(
            members: members,
            cardFrames: frames
        )

        XCTAssertEqual(ordered.count, 2)
        XCTAssertFalse(
            BrowserSplitCardLift.isOverDivider(
                CGPoint(x: 150, y: 300),
                orderedCardFrames: ordered
            ),
            "The middle of a card is never a divider."
        )
    }

    // MARK: - Fixtures

    private static let leading = BrowserSplitCardTestFixture.leadingTabID
    private static let middle = BrowserSplitCardTestFixture.middleTabID
    private static let trailing = BrowserSplitCardTestFixture.trailingTabID

    private static func picksUp(
        modifiers: BrowserKeyboardModifierFlags = [.command, .shift],
        isInsideCard: Bool = true,
        isOverDivider: Bool = false,
        memberCount: Int = 2,
        isDraggingSidebarItem: Bool = false,
        isCommandPalettePresented: Bool = false
    ) -> Bool {
        BrowserSplitCardLift.picksUp(
            modifiers: modifiers,
            isInsideCard: isInsideCard,
            isOverDivider: isOverDivider,
            memberCount: memberCount,
            isDraggingSidebarItem: isDraggingSidebarItem,
            isCommandPalettePresented: isCommandPalettePresented
        )
    }

    private static func isOverDivider(atX x: CGFloat, in cards: [CGRect]) -> Bool {
        BrowserSplitCardLift.isOverDivider(
            CGPoint(x: x, y: 300),
            orderedCardFrames: cards
        )
    }

    private static func gapIndex(
        atX x: CGFloat,
        in frames: [UUID: CGRect],
        lifted: UUID,
        layoutDirection: LayoutDirection = .leftToRight
    ) -> Int {
        BrowserSplitCardLift.gapIndex(
            at: CGPoint(x: x, y: 300),
            cardFrames: frames,
            lifted: lifted,
            layoutDirection: layoutDirection
        )
    }

    /// Three 300pt cards with an 8pt gap: midpoints at 150, 458, and 766.
    private static func cardFrames(count: Int) -> [CGRect] {
        frames(widths: Array(repeating: 300, count: count))
    }

    private static func registeredFrames(count: Int) -> [UUID: CGRect] {
        registeredFrames(
            members: Array(BrowserSplitCardTestFixture.members.prefix(count)),
            widths: Array(repeating: 300, count: count)
        )
    }

    /// Card frames as the row would register them for `members` in the order
    /// given: the first member in the leading column, and so on.
    private static func registeredFrames(
        members: [BrowserSplitCardTestFixture.Member],
        widths: [CGFloat]
    ) -> [UUID: CGRect] {
        Dictionary(
            uniqueKeysWithValues: zip(members.map(\.id), frames(widths: widths))
        )
    }

    private static func frames(widths: [CGFloat]) -> [CGRect] {
        let gap = BrowserSplitLayoutMetrics.interCardGap
        var origin: CGFloat = 0
        var frames: [CGRect] = []
        for width in widths {
            frames.append(CGRect(x: origin, y: 0, width: width, height: 600))
            origin += width + gap
        }
        return frames
    }
}

/// The carry itself: what a pickup stages, what promotes it into a carry, what a
/// pointer sample changes, when the snapshot is allowed to arrive, and what a
/// release, a cancel, and every interruption each leave behind.
@MainActor
final class BrowserSplitCardLiftStateTests: XCTestCase {

    // MARK: - Staging and promotion

    /// The pickup completes without WebKit. The card is carried from the first
    /// frame; the picture is a later improvement to something already moving.
    func testAPickupCarriesTheCardBeforeAnySnapshotExists() {
        let state = BrowserSplitCardLiftState()

        let token = state.reserve()
        XCTAssertTrue(
            state.begin(
                token: token,
                tabID: Self.tabID,
                originIndex: 1,
                cardFrame: Self.cardFrame,
                pointer: CGPoint(x: 500, y: 300),
                surfaceOrigin: Self.surfaceOrigin
            )
        )

        XCTAssertEqual(state.carriedTabID, Self.tabID)
        XCTAssertTrue(state.isCarrying)
        XCTAssertNil(state.lift?.snapshot)
        XCTAssertEqual(state.lift?.gapIndex, 1, "The gap starts where the card was.")
        XCTAssertEqual(state.lift?.cardSize, Self.cardFrame.size)
    }

    /// Staging is inert. A press that turns out to be over a divider, or over no
    /// card, has taken nothing and holds nothing.
    func testAStagedPickupChangesNothingUntilItIsPromoted() {
        let state = BrowserSplitCardLiftState()

        let token = state.reserve()

        XCTAssertNil(state.lift)
        XCTAssertFalse(state.isCarrying)

        state.discard(token)

        XCTAssertNil(state.lift)
        XCTAssertFalse(state.isCarrying)
    }

    /// A discarded pickup cannot be promoted afterwards, however late the
    /// attempt arrives.
    func testADiscardedPickupCannotBecomeACarry() {
        let state = BrowserSplitCardLiftState()
        let token = state.reserve()
        state.discard(token)

        XCTAssertFalse(Self.promote(state, token: token))
        XCTAssertNil(state.lift)
    }

    // MARK: - The carry

    // MARK: - The picture

    /// A picture asked for by a pickup that never became a carry belongs to
    /// nothing on screen.
    func testASnapshotForADiscardedPickupIsRefused() {
        let state = BrowserSplitCardLiftState()
        let refused = state.reserve()
        state.discard(refused)
        let carried = state.reserve()
        Self.promote(state, token: carried)

        state.attach(snapshot: Self.image, token: refused)

        XCTAssertNil(state.lift?.snapshot)
    }

    /// Picking the same card up twice in quick succession leaves the first
    /// request in flight. Its answer pictures a row that has already moved on.
    func testASnapshotFromAnEarlierCarryOfTheSameCardIsRefused() {
        let state = BrowserSplitCardLiftState()
        let first = state.reserve()
        Self.promote(state, token: first)
        _ = state.drop()
        let second = state.reserve()
        Self.promote(state, token: second)

        state.attach(snapshot: Self.image, token: first)

        XCTAssertNil(
            state.lift?.snapshot,
            "The tab matches; the carry does not, which is the answer that counts."
        )

        state.attach(snapshot: Self.image, token: second)

        XCTAssertEqual(state.lift?.snapshot, Self.image)
    }

    // MARK: - Release, cancel, abandon

    /// The release hands back the slot the gap was standing in — the same index
    /// the row has already drawn — and stops the carry, which is what puts the
    /// card back on show under the settling preview.
    func testAReleaseCommitsTheSlotTheGapIsStandingIn() {
        let state = Self.carryingState()
        state.update(
            pointer: CGPoint(x: 800, y: 320),
            gapIndex: 2,
            surfaceOrigin: Self.surfaceOrigin
        )

        let move = state.drop()

        XCTAssertEqual(move?.tabID, Self.tabID)
        XCTAssertEqual(move?.memberIndex, 2)
        XCTAssertEqual(state.lift?.isSettling, true)
        XCTAssertNil(state.carriedTabID, "A settling card is back in the row.")
        XCTAssertFalse(state.isCarrying)
    }

    /// Escape and a right-click end the carry without a move, and without ever
    /// having made one: nothing here has touched the session.
    func testACancelReturnsTheCardWithoutAMove() {
        let state = Self.carryingState()
        state.update(
            pointer: CGPoint(x: 800, y: 320),
            gapIndex: 2,
            surfaceOrigin: Self.surfaceOrigin
        )

        state.cancel()

        XCTAssertEqual(state.lift?.isSettling, true)
        XCTAssertNil(state.carriedTabID)
        XCTAssertEqual(
            state.lift?.originIndex,
            1,
            "The row puts the card back where the carry found it."
        )
    }

    /// A settling preview is not a carry, so nothing may restart one.
    func testASettlingCarryTakesNoMorePointerSamples() {
        let state = Self.carryingState()
        state.cancel()

        state.update(
            pointer: CGPoint(x: 900, y: 100),
            gapIndex: 0,
            surfaceOrigin: Self.surfaceOrigin
        )

        XCTAssertEqual(state.lift?.gapIndex, 1)
    }

    /// A card that left the row has nothing to settle onto.
    func testAbandoningACarryLeavesNothingBehind() {
        let state = Self.carryingState()

        state.abandon()

        XCTAssertNil(state.lift)
        XCTAssertFalse(state.isCarrying)
    }

    // MARK: - Totality

    /// Every way a pickup can be refused, and every way a carry can be
    /// interrupted, returns the state to idle — and a pickup made straight
    /// afterwards succeeds.
    ///
    /// This is the property the whole state machine exists for. A window that
    /// can never pick a card up again is a window holding one refused or
    /// interrupted transition that left something armed, so each of them is
    /// enumerated here rather than argued about.
    func testEveryRefusedOrInterruptedTransitionReturnsToIdle() {
        let interruptions: [(String, (BrowserSplitCardLiftState) -> Void)] = [
            (
                "a pickup refused before it was promoted",
                { state in
                    state.discard(state.reserve())
                }
            ),
            (
                "a pickup refused twice over",
                { state in
                    let token = state.reserve()
                    state.discard(token)
                    state.discard(token)
                }
            ),
            (
                "a cancel with nothing in flight",
                { state in
                    state.cancel()
                }
            ),
            (
                "a cancel of a staged pickup",
                { state in
                    _ = state.reserve()
                    state.cancel()
                }
            ),
            (
                "a release with nothing in flight",
                { state in
                    XCTAssertNil(state.drop())
                }
            ),
            (
                "an abandon with nothing in flight",
                { state in
                    state.abandon()
                }
            ),
            (
                "a carry released",
                { state in
                    Self.promote(state, token: state.reserve())
                    _ = state.drop()
                }
            ),
            (
                "a carry cancelled",
                { state in
                    Self.promote(state, token: state.reserve())
                    state.cancel()
                }
            ),
            (
                "a carry cancelled twice",
                { state in
                    Self.promote(state, token: state.reserve())
                    state.cancel()
                    state.cancel()
                }
            ),
            (
                "a carry released and then cancelled",
                { state in
                    Self.promote(state, token: state.reserve())
                    _ = state.drop()
                    state.cancel()
                }
            ),
            (
                "a carry abandoned mid-flight",
                { state in
                    Self.promote(state, token: state.reserve())
                    state.abandon()
                }
            ),
            (
                "a carry abandoned while settling",
                { state in
                    Self.promote(state, token: state.reserve())
                    _ = state.drop()
                    state.abandon()
                }
            ),
            (
                "a snapshot arriving for nothing",
                { state in
                    state.attach(snapshot: Self.image, token: state.reserve())
                }
            ),
        ]

        for (description, interruption) in interruptions {
            let state = BrowserSplitCardLiftState()
            interruption(state)

            XCTAssertFalse(
                state.isCarrying,
                "\(description) left the pointer believing it holds a card."
            )

            let token = state.reserve()

            XCTAssertTrue(
                state.begin(
                    token: token,
                    tabID: Self.tabID,
                    originIndex: 1,
                    cardFrame: Self.cardFrame,
                    pointer: CGPoint(x: 500, y: 300),
                    surfaceOrigin: Self.surfaceOrigin
                ),
                "No card could be picked up after \(description)."
            )
            XCTAssertEqual(state.carriedTabID, Self.tabID)
            XCTAssertTrue(state.isCarrying)
        }
    }

    /// A pickup made while another carry is still settling supersedes it
    /// outright rather than inheriting anything from it.
    func testAPickupDuringASettleStartsCleanly() {
        let state = Self.carryingState()
        state.update(
            pointer: CGPoint(x: 800, y: 320),
            gapIndex: 2,
            surfaceOrigin: Self.surfaceOrigin
        )
        state.attach(snapshot: Self.image, token: Self.token(of: state))
        _ = state.drop()

        let token = state.reserve()
        state.begin(
            token: token,
            tabID: Self.otherTabID,
            originIndex: 0,
            cardFrame: Self.cardFrame,
            pointer: CGPoint(x: 100, y: 100),
            surfaceOrigin: Self.surfaceOrigin
        )

        XCTAssertEqual(state.carriedTabID, Self.otherTabID)
        XCTAssertEqual(state.lift?.gapIndex, 0)
        XCTAssertNil(state.lift?.snapshot, "The new carry has no picture yet.")
        XCTAssertEqual(state.lift?.isSettling, false)
    }

    // MARK: - Fixtures

    private static let tabID = BrowserSplitCardTestFixture.middleTabID
    private static let otherTabID = BrowserSplitCardTestFixture.leadingTabID
    private static let cardFrame = CGRect(x: 308, y: 0, width: 400, height: 600)
    private static let surfaceOrigin = CGPoint(x: 260, y: 40)
    private static let image = NSImage(size: CGSize(width: 4, height: 4))

    private static func carryingState() -> BrowserSplitCardLiftState {
        let state = BrowserSplitCardLiftState()
        promote(state, token: state.reserve())
        return state
    }

    @discardableResult
    private static func promote(
        _ state: BrowserSplitCardLiftState,
        token: BrowserSplitCardLiftToken
    ) -> Bool {
        state.begin(
            token: token,
            tabID: tabID,
            originIndex: 1,
            cardFrame: cardFrame,
            pointer: CGPoint(x: 500, y: 300),
            surfaceOrigin: surfaceOrigin
        )
    }

    private static func token(of state: BrowserSplitCardLiftState) -> BrowserSplitCardLiftToken {
        state.lift?.token ?? BrowserSplitCardLiftToken(sequence: 0)
    }

}

private enum BrowserSplitCardTestFixture {
    static let leadingTabID = tabID(0x11)
    static let middleTabID = tabID(0x12)
    static let trailingTabID = tabID(0x13)

    static let members = [
        member(id: leadingTabID, title: "Release Notes"),
        member(id: middleTabID, title: "Layout Research"),
        member(id: trailingTabID, title: "Split View Spec"),
    ]

    /// A card of the row: only its identity matters to the lift.
    struct Member: Identifiable, Equatable {
        let id: UUID
        let title: String
    }

    private static func member(id: UUID, title: String) -> Member {
        Member(id: id, title: title)
    }

    private static func tabID(_ finalByte: UInt8) -> UUID {
        uuid(finalByte)
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x54,
                0x45, 0x53,
                0x54, 0x53,
                0x50, 0x4C, 0x49, 0x54, 0x00, finalByte
            ))
    }
}
