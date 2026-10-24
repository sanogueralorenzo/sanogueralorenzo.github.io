import CoreGraphics
import Foundation
import XCTest

@testable import Crest

/// Drag-to-split: where a tab dropped on the content area lands, and when the
/// content area refuses it outright.
@MainActor
final class BrowserSplitDropTests: XCTestCase {

    // MARK: - Acceptance: what the zone itself refuses

    /// Only a tab becomes a card. A folder has no page, and a whole group would
    /// have to mean "present these instead", which is not a defined gesture.
    func testTheContentZoneTakesTabsOnly() {
        let assignment = Self.assignment
        let zones = [
            BrowserSidebarReorderZone(
                target: .splitContent(assignment),
                frame: Self.contentFrame
            )
        ]
        let point = CGPoint(x: 400, y: 300)

        XCTAssertEqual(
            BrowserSidebarReorderZone.aimed(
                at: point,
                in: zones,
                accepting: Self.tabItem(in: assignment)
            )?
            .target,
            .splitContent(assignment)
        )
        XCTAssertNil(
            BrowserSidebarReorderZone.aimed(
                at: point,
                in: zones,
                accepting: Self.folderItem(in: assignment)
            )
        )
        // A split joins the cards on show only when the core offers it.
        XCTAssertNil(
            BrowserSidebarReorderZone.aimed(
                at: point,
                in: zones,
                accepting: Self.groupItem(in: assignment),
                plan: Self.plan(splitRefusal: .alreadyInSplit(AlreadyInSplit(tabID: UUID())))
            )
        )
    }

    /// A split never spans Spaces, so a tab from another one is refused where it
    /// would otherwise be silently relocated first.
    func testTheContentZoneRefusesATabFromAnotherSpace() {
        let zones = [
            BrowserSidebarReorderZone(
                target: .splitContent(Self.assignment),
                frame: Self.contentFrame
            )
        ]

        XCTAssertNil(
            BrowserSidebarReorderZone.aimed(
                at: CGPoint(x: 400, y: 300),
                in: zones,
                accepting: Self.tabItem(
                    in: BrowserSpaceRuntimeAssignment(
                        spaceID: UUID(),
                        profileID: UUID()
                    )
                )
            )
        )
    }

    /// The content area is the least specific zone in the window: a sidebar
    /// floating over it keeps every drop that lands on a list.
    func testAnOverlappingSectionOutranksTheContentArea() {
        let section = BrowserSidebarReorderSection.tabs(
            placement: .current,
            folderID: nil
        )
        let zones = [
            BrowserSidebarReorderZone(
                target: .splitContent(Self.assignment),
                frame: Self.contentFrame
            ),
            BrowserSidebarReorderZone(
                target: .section(section),
                frame: CGRect(x: 0, y: 0, width: 260, height: 600)
            ),
        ]

        XCTAssertEqual(
            BrowserSidebarReorderZone.aimed(
                at: CGPoint(x: 120, y: 300),
                in: zones,
                accepting: Self.tabItem(in: Self.assignment)
            )?
            .target,
            .section(section)
        )
        XCTAssertEqual(
            BrowserSidebarReorderZone.aimed(
                at: CGPoint(x: 600, y: 300),
                in: zones,
                accepting: Self.tabItem(in: Self.assignment)
            )?
            .target,
            .splitContent(Self.assignment),
            "Past the sidebar there is nothing else to outrank it."
        )
    }

    /// The seam between two runs belongs to the sidebar, not to the page behind
    /// it.
    ///
    /// A sidebar wraps its runs tightly, so aiming at one means aiming into the
    /// space beside it — that is how a list is appended to, and it is the only
    /// way to reach the pinned grid, which sits above the scrolling list and is
    /// a band a dozen points tall until a first tab is pinned. A floating
    /// sidebar is drawn on top of the content area, so containment alone hands
    /// every one of those seams to the page: the run stops answering, and when
    /// the content area declines the drop the drag resolves nowhere at all.
    func testASeamBetweenRunsOutranksTheContentAreaBehindIt() {
        let pinned = BrowserSidebarReorderSection.tabs(
            placement: .pinned,
            folderID: nil
        )
        let current = BrowserSidebarReorderSection.tabs(
            placement: .current,
            folderID: nil
        )
        let zones = [
            // A floating sidebar is drawn on top of the page, so the content
            // area's zone spans the whole window rather than starting beside
            // the sidebar.
            BrowserSidebarReorderZone(
                target: .splitContent(Self.assignment),
                frame: CGRect(x: 0, y: 0, width: 1_160, height: 1_000)
            ),
            // An unfilled grid: a band, with the address field above it.
            BrowserSidebarReorderZone(
                target: .section(pinned),
                frame: CGRect(x: 8, y: 96, width: 264, height: 12)
            ),
            BrowserSidebarReorderZone(
                target: .section(current),
                frame: CGRect(x: 0, y: 240, width: 280, height: 300)
            ),
        ]

        XCTAssertEqual(
            BrowserSidebarReorderZone.aimed(
                at: CGPoint(x: 140, y: 60),
                in: zones,
                accepting: Self.tabItem(in: Self.assignment)
            )?
            .target,
            .section(pinned),
            "Above the grid, the grid is what the pointer is aiming at."
        )
        XCTAssertEqual(
            BrowserSidebarReorderZone.aimed(
                at: CGPoint(x: 140, y: 200),
                in: zones,
                accepting: Self.tabItem(in: Self.assignment)
            )?
            .target,
            .section(current),
            "Below the grid, the nearer run wins on the same terms."
        )
        XCTAssertEqual(
            BrowserSidebarReorderZone.aimed(
                at: CGPoint(x: 600, y: 60),
                in: zones,
                accepting: Self.tabItem(in: Self.assignment)
            )?
            .target,
            .splitContent(Self.assignment),
            "Past the sidebar's own column no run answers, and the page does."
        )
        XCTAssertEqual(
            BrowserSidebarReorderZone.aimed(
                at: CGPoint(x: 140, y: 800),
                in: zones,
                accepting: Self.tabItem(in: Self.assignment)
            )?
            .target,
            .splitContent(Self.assignment),
            "Nor does a run answer from further than its slop reaches."
        )
    }

    func testHiddenSpaceCannotClaimThePageBeyondTheSidebarBuffer() {
        for sidebarWidth: CGFloat in [220, 360] {
            let state = Self.stateWithCards(count: 1)
            let viewportID = UUID()
            state.register(sidebarViewport: CGRect(x: 0, y: 0, width: sidebarWidth, height: 600), for: viewportID)
            let current = BrowserSidebarReorderSection.tabs(placement: .current, folderID: nil)
            for x in [CGFloat(0), sidebarWidth] {
                state.register(
                    zone: BrowserSidebarReorderZone(
                        target: .section(current),
                        frame: CGRect(x: x, y: 150, width: sidebarWidth, height: 400)),
                    for: UUID(), sidebarViewportID: viewportID)
            }
            // Content begins at the visible sidebar edge, including narrow windows.
            state.register(
                zone: BrowserSidebarReorderZone(
                    target: .splitContent(Self.assignment),
                    frame: CGRect(x: sidebarWidth, y: 0, width: 900, height: 600)), for: UUID())
            state.begin(item: Self.tabItem(in: Self.assignment), section: current, at: CGPoint(x: 100, y: 200))
            state.update(pointer: CGPoint(x: sidebarWidth + 12, y: 300))
            XCTAssertEqual(
                state.resolvedTarget?.section, current, "A small buffer keeps a near-edge drag in the sidebar.")
            state.update(pointer: CGPoint(x: sidebarWidth + 25, y: 300))
            XCTAssertEqual(state.resolvedTarget?.kind, .splitInsert(assignment: Self.assignment, index: 0))
            XCTAssertTrue(state.hasEnteredSplitContent)
            state.update(pointer: CGPoint(x: sidebarWidth + 850, y: 300))
            XCTAssertEqual(state.resolvedTarget?.kind, .splitInsert(assignment: Self.assignment, index: 1))
            state.cancel()
        }
    }

    // MARK: - Acceptance: what the presented cards refuse

    /// A tab already on show has nothing to join, and the core refuses the join.
    /// That covers the lone tab in an unsplit window dropped onto itself as much
    /// as a member of a live split.
    func testAPresentedTabIsRefusedByItsOwnContentArea() {
        let presented = UUID()
        let state = Self.stateWithCards(count: 2, firstTabID: presented)

        state.begin(
            item: Self.tabItem(in: Self.assignment, tabID: presented),
            section: .tabs(placement: .current, folderID: nil),
            at: CGPoint(x: 100, y: 20),
            plan: Self.plan(splitRefusal: .alreadyInSplit(AlreadyInSplit(tabID: presented)))
        )
        state.update(pointer: CGPoint(x: 460, y: 300))

        XCTAssertNil(state.resolvedTarget)
        XCTAssertEqual(
            state.liftTargetShape,
            .row,
            "An unresolved drag holds the shape it started as."
        )
        XCTAssertFalse(state.hasEnteredSplitContent)
        state.cancel()
    }

    /// A full group shows no insertion point, because the core refuses the join
    /// and the placeholder would be a promise nobody keeps.
    func testAFullGroupOffersNoInsertionPoint() {
        let state = Self.stateWithCards(
            count: CapacityLimits.current.splitMembers
        )

        state.begin(
            item: Self.tabItem(in: Self.assignment),
            section: .tabs(placement: .current, folderID: nil),
            at: CGPoint(x: 100, y: 20),
            plan: Self.plan(
                splitRefusal: .splitLimitReached(SplitLimitReached(limit: CapacityLimits.current.splitMembers)))
        )
        state.update(pointer: CGPoint(x: 460, y: 300))

        XCTAssertNil(state.resolvedTarget)
        state.cancel()
    }

    /// One content area presents one Space, but its cards outlive the
    /// presentation: the Space just switched away from still has cards in the
    /// registry, at the very rectangle the new Space now occupies. They must not
    /// be counted into the drop the pointer is making, or the index would be off
    /// and a two-card split would report itself full.
    ///
    /// The frames deliberately match the live ones. Nothing about the content
    /// area moves when the Space in it changes, so there is no geometry here to
    /// tell the two apart — the Space each card names is the only thing that can.
    func testAnotherSpacesCardsAreNotCountedIntoThisDrop() {
        let state = Self.stateWithCards(count: 2)
        for frame in Self.presentedCardFrames(count: 2) {
            state.register(
                splitCardFrame: frame,
                for: UUID(),
                in: Self.otherAssignment,
                owner: UUID()
            )
        }

        state.begin(
            item: Self.tabItem(in: Self.assignment),
            section: .tabs(placement: .current, folderID: nil),
            at: CGPoint(x: 100, y: 20)
        )
        state.update(pointer: CGPoint(x: 600, y: 300))

        XCTAssertEqual(
            state.resolvedTarget?.kind,
            .splitInsert(assignment: Self.assignment, index: 1),
            "The other Space's two cards would have filled the group outright."
        )
        state.cancel()
    }

    /// A card that unregisters as the layout swaps hosts must not take the
    /// replacement's registration with it.
    func testAStaleCardRemovalCannotClearItsReplacement() {
        let state = BrowserSidebarReorderState()
        let tabID = UUID()
        let departing = UUID()
        let arriving = UUID()
        let frame = CGRect(x: 0, y: 0, width: 900, height: 600)

        state.register(
            splitCardFrame: frame,
            for: tabID,
            in: Self.assignment,
            owner: departing
        )
        state.register(
            splitCardFrame: frame,
            for: tabID,
            in: Self.assignment,
            owner: arriving
        )
        state.removeSplitCardFrame(for: tabID, owner: departing)

        XCTAssertEqual(state.orderedSplitCardFrames, [frame])

        state.removeSplitCardFrame(for: tabID, owner: arriving)
        XCTAssertTrue(state.orderedSplitCardFrames.isEmpty)
    }

    /// Entering the content area is a one-way door for the length of the drag:
    /// the columns layout it opens must not close again when the pointer leaves,
    /// or the live web view changes hosts twice per hover.
    func testTheContentAreaStaysEnteredForTheRestOfTheDrag() {
        let state = Self.stateWithCards(count: 1)

        state.begin(
            item: Self.tabItem(in: Self.assignment),
            section: .tabs(placement: .current, folderID: nil),
            at: CGPoint(x: 100, y: 20)
        )
        state.update(pointer: CGPoint(x: 460, y: 300))
        XCTAssertTrue(state.hasEnteredSplitContent)

        // Back over the sidebar: the placeholder goes, the layout stays.
        state.update(pointer: CGPoint(x: 100, y: 20))
        XCTAssertNil(state.resolvedTarget)
        XCTAssertTrue(state.hasEnteredSplitContent)

        state.cancel()
        XCTAssertFalse(state.hasEnteredSplitContent)
    }

    // MARK: - Fixtures

    private static let assignment = BrowserSpaceRuntimeAssignment(
        spaceID: uuid(1),
        profileID: uuid(2)
    )

    /// A Space this window is not presenting: the one it switched away from, or
    /// the one it is switching to while the change animates.
    private static let otherAssignment = BrowserSpaceRuntimeAssignment(
        spaceID: uuid(3),
        profileID: uuid(4)
    )

    private static let contentFrame = CGRect(
        x: 260,
        y: 0,
        width: 900,
        height: 600
    )

    /// Three 300pt cards with an 8pt gap: midpoints at 150, 458, and 766.

    private static func frames(
        widths: [CGFloat],
        placeholderWidth: CGFloat? = nil,
        placeholderIndex: Int? = nil
    ) -> [CGRect] {
        let gap = BrowserSplitLayoutMetrics.interCardGap
        var origin: CGFloat = 0
        var frames: [CGRect] = []
        for (index, width) in widths.enumerated() {
            if index == placeholderIndex, let placeholderWidth {
                origin += placeholderWidth + gap
            }
            frames.append(CGRect(x: origin, y: 0, width: width, height: 600))
            origin += width + gap
        }
        return frames
    }

    private static func index(atX x: CGFloat, in frames: [CGRect]) -> Int {
        BrowserSplitColumnLayout.insertionIndex(
            at: CGPoint(x: x, y: 300),
            orderedCardFrames: frames
        )
    }

    /// Where a content area presenting `count` cards puts them: equal widths
    /// filling `contentFrame`, with the row's own gap between them.
    private static func presentedCardFrames(count: Int) -> [CGRect] {
        guard count > 0 else { return [] }
        let gap = BrowserSplitLayoutMetrics.interCardGap
        let width =
            (contentFrame.width - gap * CGFloat(count - 1)) / CGFloat(count)
        return (0..<count).map { index in
            CGRect(
                x: contentFrame.minX + (width + gap) * CGFloat(index),
                y: contentFrame.minY,
                width: width,
                height: contentFrame.height
            )
        }
    }

    /// A state whose content zone spans `contentFrame` and holds `count` cards
    /// of equal width inside it.
    private static func stateWithCards(
        count: Int,
        firstTabID: UUID? = nil
    ) -> BrowserSidebarReorderState {
        let state = BrowserSidebarReorderState()
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .splitContent(assignment),
                frame: contentFrame
            ),
            for: UUID()
        )
        for (index, frame) in presentedCardFrames(count: count).enumerated() {
            state.register(
                splitCardFrame: frame,
                for: index == 0 ? (firstTabID ?? UUID()) : UUID(),
                in: assignment,
                owner: UUID()
            )
        }
        return state
    }

    /// A lift the core lets into the current tabs, and into the cards on show
    /// only as `splitRefusal` says.
    private static func plan(splitRefusal: Rejection?) -> BrowserSidebarLiftPlan {
        BrowserSidebarLiftPlan(
            selection: TabSelection(tabIDs: [], folderIDs: [], memberTabIDs: []),
            targets: DropTargetList(
                refusal: nil, lists: [ListDropTarget(section: .current, folderID: nil)], spaceIDs: [],
                split: SplitDropTarget(tabID: UUID(), refusal: splitRefusal), folderAroundTabIDs: []))
    }

    private static func tabItem(
        in assignment: BrowserSpaceRuntimeAssignment,
        tabID: UUID = UUID()
    ) -> BrowserSidebarReorderItem {
        .tab(
            BrowserTabDragItem(
                tabID: tabID,
                spaceID: assignment.spaceID,
                profileID: assignment.profileID
            )
        )
    }

    private static func folderItem(
        in assignment: BrowserSpaceRuntimeAssignment
    ) -> BrowserSidebarReorderItem {
        .folder(
            BrowserFolderDragItem(
                folderID: UUID(),
                spaceID: assignment.spaceID,
                profileID: assignment.profileID
            )
        )
    }

    private static func groupItem(
        in assignment: BrowserSpaceRuntimeAssignment
    ) -> BrowserSidebarReorderItem {
        .splitGroup(
            BrowserSplitGroupDragItem(
                groupID: UUID(),
                spaceID: assignment.spaceID,
                profileID: assignment.profileID,
                memberTabIDs: [UUID(), UUID()]
            )
        )
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x53, 0x50, 0x4C, 0x49, 0x54, 0x44, 0x52, 0x4F,
                0x50, 0x50, 0x4F, 0x4C, 0x49, 0x43, 0x59, finalByte
            )
        )
    }
}
