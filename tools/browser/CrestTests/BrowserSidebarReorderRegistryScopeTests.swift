import CoreGraphics
import Foundation
import XCTest

@testable import Crest

/// Reorder capacity and ordering exclude other Spaces retained by the pager.
@MainActor
final class BrowserSidebarReorderRegistryScopeTests: XCTestCase {

    /// A drag counts and orders among its own Space's tiles, so a Space
    /// alongside can neither fill its grid nor push its insertion point along.
    ///
    /// Eleven foreign tiles and two of its own is past the cap, and four of the
    /// foreign ones sit on the pointer's own line, to its left. Counted
    /// together, the grid has no room at all, and the slot the pointer is over
    /// is the sixth rather than the second.
    func testAForeignSpacesPinnedRowsNeitherFillNorReorderThisDragsGrid() {
        let fixture = ReorderRegistryFixture(ownPinCount: 2)
        let state = fixture.sidebarInteraction.sidebarReorderState
        fixture.register(in: state)

        fixture.liftTheJoiner(in: state, to: CGPoint(x: 144, y: 92))

        XCTAssertEqual(
            state.resolvedTarget?.kind,
            .insert(
                section: .tabs(placement: .pinned, folderID: nil),
                beforeID: .tab(fixture.ownPins[1].id),
                index: 1
            ),
            "A grid holding two tiles has room, and the pointer is over its "
                + "second slot — whatever the Space alongside has pinned."
        )
        XCTAssertEqual(
            state.liftTargetShape,
            .pinnedTile,
            "A resolved pinned slot morphs the lift into the tile it will be."
        )
        XCTAssertNil(
            state.indicator(for: .tab(fixture.foreignPins[0].id)),
            "A row this drag cannot land beside must not draw its seam."
        )
        XCTAssertEqual(
            state.displacement(for: .tab(fixture.foreignPins[0].id)),
            .zero,
            "Nor step aside for it."
        )
    }

    /// The cap still bites where it is meant to. Scoping the count must not
    /// become a way of ignoring it: a grid already full of this Space's own tabs
    /// has nowhere to put another, so the lift over it says why in the core's
    /// words, and releasing there commits nothing.
    func testAGridFullOfItsOwnTabsStillRefusesAnIncomingPin() {
        let fixture = ReorderRegistryFixture(
            ownPinCount: TabPlacement.pinnedCapacity
        )
        let state = fixture.sidebarInteraction.sidebarReorderState
        fixture.register(in: state)

        fixture.liftTheJoiner(in: state, to: CGPoint(x: 144, y: 92))

        XCTAssertEqual(
            state.constraintMessage,
            Rejection.pinnedTabsFull(PinnedTabsFull(capacity: TabPlacement.pinnedCapacity)).placementExplanation,
            "A grid at the cap has to refuse the drop, and say why, instead of "
                + "promising a slot the commit would decline."
        )
        XCTAssertNil(
            state.end(),
            "Releasing over a refused target commits nothing."
        )
    }

    // MARK: - Presented cards

    /// A drag into the content area joins the cards of the Space that content
    /// area is presenting, and counts no others against the group's capacity.
    ///
    /// Two Spaces have cards registered because one content area presents one
    /// Space at a time and its cards outlive the presentation: the arriving
    /// cards measure themselves before SwiftUI runs the departing ones'
    /// `onDisappear`, so a Space change leaves both sets in the registry for as
    /// long as it takes to animate. Two two-card splits is
    /// `CapacityLimits.current.splitMembers` exactly, so counted together the
    /// group is full and the drag is refused a split that has two slots free —
    /// refused in silence, since no resolved target means no placeholder, no
    /// insertion line, and no reason given.
    ///
    /// Geometry cannot separate them. Both Spaces lay their cards out in the
    /// same content area, and the content area does not move an inch when the
    /// Space in it changes, so the two sets occupy the very same rectangles.
    /// A row that moves between lists is two views for a moment. The one
    /// leaving can measure itself again during its exit, after the arriving
    /// one did; when it leaves, the row keeps the arriving view's frame
    /// instead of losing its registration until something moves it again.
    func testARowKeepsItsFrameWhenTheViewItLeftMeasuresLast() {
        let state = BrowserSidebarReorderState()
        let space = BrowserSpaceRuntimeAssignment(spaceID: UUID(), profileID: UUID())
        let id = BrowserSidebarReorderItemID.tab(UUID())
        let (leaving, arriving) = (UUID(), UUID())
        func row(y: CGFloat, folderID: UUID? = nil) -> BrowserSidebarReorderRow {
            BrowserSidebarReorderRow(
                id: id, space: space, section: .tabs(placement: .current, folderID: folderID),
                frame: CGRect(x: 0, y: y, width: 240, height: 40))
        }
        let folder = UUID()
        state.register(row: row(y: 200, folderID: folder), owner: leaving)
        state.register(row: row(y: 40), owner: arriving)
        state.register(row: row(y: 190, folderID: folder), owner: leaving)
        state.removeRow(id, owner: leaving)

        XCTAssertEqual(state.frame(ofRow: id), CGRect(x: 0, y: 40, width: 240, height: 40))
        state.removeRow(id, owner: arriving)
        XCTAssertNil(state.frame(ofRow: id), "The row goes once no view shows it.")
    }

    func testAnotherSpacesCardsCannotFillThisDragsSplit() {
        let fixture = SplitCardRegistryFixture(
            ownCardCount: 2,
            foreignCardCount: 2
        )
        let state = fixture.sidebarInteraction.sidebarReorderState
        fixture.register(in: state)

        fixture.liftTheJoiner(in: state, to: fixture.pointerInSecondOwnCard)

        XCTAssertEqual(
            state.resolvedTarget?.kind,
            .splitInsert(assignment: fixture.ownSpace, index: 1),
            "Two cards on show leave two slots free, whatever the Space this "
                + "window has just left still has registered."
        )
        XCTAssertEqual(
            state.liftTargetShape,
            .webpageCard,
            "A resolved card slot morphs the lift into the card it will be."
        )
        XCTAssertTrue(
            state.hasEnteredSplitContent,
            "A resolved card slot is what opens the columns layout."
        )
    }

}

// MARK: - Fixture

private let pinnedSection = BrowserSidebarReorderSection.tabs(
    placement: .pinned,
    folderID: nil
)
private let currentSection = BrowserSidebarReorderSection.tabs(
    placement: .current,
    folderID: nil
)

/// Where a 390-point sidebar puts the runs this drag moves between. The pinned
/// zone is three tile lines deep, which is what a grid at the cap measures.
private let pinnedZone = CGRect(x: 8, y: 60, width: 374, height: 192)
private let currentZone = CGRect(x: 8, y: 240, width: 374, height: 300)
private let joinerRow = CGRect(x: 8, y: 260, width: 374, height: 44)
private let pageWidth: CGFloat = 390
private let tileSize = CGSize(width: 88, height: 64)
private let tileStride = CGSize(width: 92, height: 64)
private let gridColumns = 4

/// Reading-order cell geometry for a grid on the page `pageOffset` away.
private func tile(_ index: Int, pageOffset: CGFloat) -> CGRect {
    CGRect(
        x: pinnedZone.minX
            + pageOffset
            + CGFloat(index % gridColumns) * tileStride.width,
        y: pinnedZone.minY + CGFloat(index / gridColumns) * tileStride.height,
        width: tileSize.width,
        height: tileSize.height
    )
}

/// One window retains both the active Space and an adjacent pager page.
@MainActor
private struct ReorderRegistryFixture {
    let sidebarInteraction: BrowserSidebarInteractionState
    let browser: BrowserStore
    let ownPins: [TabState.Seed]
    let foreignPins: [TabState.Seed]
    let joiner: TabState.Seed

    private let ownSpaceID = uuid(0x01)
    private let ownProfileID = uuid(0x02)
    private let foreignSpaceID = uuid(0x03)
    private let foreignProfileID = uuid(0x04)

    init(ownPinCount: Int) {
        ownPins = (0..<ownPinCount).map { index in
            makeTab(
                id: uuid(UInt8(0x10 + index)),
                title: "Own Pin \(index)",
                placement: .pinned
            )
        }
        // One short of the cap, so nothing here is a grid that is genuinely
        // full — only the sum of two grids is.
        foreignPins = (0..<(TabPlacement.pinnedCapacity - 1)).map { index in
            makeTab(
                id: uuid(UInt8(0x50 + index)),
                title: "Foreign Pin \(index)",
                placement: .pinned
            )
        }
        joiner = makeTab(
            id: uuid(0x40),
            title: "Joiner",
            placement: .current
        )
        let own = makeSpace(
            id: ownSpaceID,
            profileID: ownProfileID,
            name: "Dragging",
            tabs: ownPins + [joiner]
        )
        let foreign = makeSpace(
            id: foreignSpaceID,
            profileID: foreignProfileID,
            name: "Alongside",
            tabs: foreignPins
        )
        browser = BrowserStore(
            seed: SessionState.Seed(spaces: [own, foreign]),
            showing: own.id, tabs: firstTabs(of: [own, foreign]),
            browsingMode: .privateBrowsing
        )
        sidebarInteraction = BrowserSidebarInteractionState.connected(to: browser)
    }

    var ownSpace: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(
            spaceID: ownSpaceID,
            profileID: ownProfileID
        )
    }

    var foreignSpace: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(
            spaceID: foreignSpaceID,
            profileID: foreignProfileID
        )
    }

    /// Registers what two sidebars on screen would: this Space's grid and
    /// current list where the pointer can reach them, and the Space alongside
    /// one page to the left, where it cannot.
    func register(in state: BrowserSidebarReorderState) {
        for (index, tab) in ownPins.enumerated() {
            state.register(
                row: BrowserSidebarReorderRow(
                    id: .tab(tab.id),
                    space: ownSpace,
                    section: pinnedSection,
                    frame: tile(index, pageOffset: 0)
                ),
                owner: UUID()
            )
        }
        state.register(
            row: BrowserSidebarReorderRow(
                id: .tab(joiner.id),
                space: ownSpace,
                section: currentSection,
                frame: joinerRow
            ),
            owner: UUID()
        )
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .section(pinnedSection),
                frame: pinnedZone
            ),
            for: UUID()
        )
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .section(currentSection),
                frame: currentZone
            ),
            for: UUID()
        )

        for (index, tab) in foreignPins.enumerated() {
            state.register(
                row: BrowserSidebarReorderRow(
                    id: .tab(tab.id),
                    space: foreignSpace,
                    section: pinnedSection,
                    frame: tile(index, pageOffset: -pageWidth)
                ),
                owner: UUID()
            )
        }
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .section(pinnedSection),
                frame: pinnedZone.offsetBy(dx: -pageWidth, dy: 0)
            ),
            for: UUID()
        )
    }

    /// Lifts the current tab out of its row and holds the pointer at `pointer`.
    /// Lifts the joiner as the sidebar does, asking the core where it may
    /// land as the lift begins.
    func liftTheJoiner(
        in state: BrowserSidebarReorderState,
        to pointer: CGPoint
    ) {
        let item = BrowserSidebarReorderItem.tab(
            BrowserTabDragItem(
                tabID: joiner.id,
                spaceID: ownSpaceID,
                profileID: ownProfileID
            )
        )
        state.begin(
            item: item,
            section: currentSection,
            at: CGPoint(x: joinerRow.midX, y: joinerRow.midY),
            plan: browser.liftPlan(for: item)
        )
        state.update(pointer: pointer)
    }
}

// MARK: - Split card fixture

/// Where a 1160-point window puts its web-content area, once a 260-point sidebar
/// has taken the leading edge.
private let splitContentZone = CGRect(x: 260, y: 60, width: 900, height: 600)

/// The sidebar row the dragged tab is lifted out of, in that window's sidebar.
private let splitJoinerRow = CGRect(x: 8, y: 200, width: 240, height: 40)

/// Where a content area presenting `count` cards puts them: equal widths filling
/// the area, with the row's own gap between them.
///
/// Both Spaces use this, because both of them are presenting into the same
/// window. That is the point — a Space change swaps what the content area holds
/// without moving the content area, so the Space left behind measured its cards
/// against the very rectangle the Space now on show is measuring against.
private func splitCardFrames(count: Int) -> [CGRect] {
    guard count > 0 else { return [] }
    let gap = BrowserSplitLayoutMetrics.interCardGap
    let width =
        (splitContentZone.width - gap * CGFloat(count - 1)) / CGFloat(count)
    return (0..<count).map { index in
        CGRect(
            x: splitContentZone.minX + (width + gap) * CGFloat(index),
            y: splitContentZone.minY,
            width: width,
            height: splitContentZone.height
        )
    }
}

/// One window's content area holding two Spaces' cards at once: the Space it is
/// presenting, and the Space it has just left, whose cards are registered at the
/// same rectangles until SwiftUI runs their disappearance.
@MainActor
private struct SplitCardRegistryFixture {
    let sidebarInteraction: BrowserSidebarInteractionState
    let browser: BrowserStore
    let ownCards: [TabState.Seed]
    let foreignCards: [TabState.Seed]
    let joiner: TabState.Seed

    private let ownCardCount: Int
    private let foreignCardCount: Int
    private let ownSpaceID = uuid(0x05)
    private let ownProfileID = uuid(0x06)
    private let foreignSpaceID = uuid(0x07)
    private let foreignProfileID = uuid(0x08)

    init(ownCardCount: Int, foreignCardCount: Int) {
        self.ownCardCount = ownCardCount
        self.foreignCardCount = foreignCardCount
        ownCards = (0..<ownCardCount).map { index in
            makeTab(
                id: uuid(UInt8(0x60 + index)),
                title: "Own Card \(index)",
                placement: .current
            )
        }
        foreignCards = (0..<foreignCardCount).map { index in
            makeTab(
                id: uuid(UInt8(0x70 + index)),
                title: "Foreign Card \(index)",
                placement: .current
            )
        }
        joiner = makeTab(
            id: uuid(0x6F),
            title: "Joiner",
            placement: .current
        )
        let own = makeSpace(
            id: ownSpaceID,
            profileID: ownProfileID,
            name: "Presenting",
            tabs: ownCards + [joiner]
        )
        let foreign = makeSpace(
            id: foreignSpaceID,
            profileID: foreignProfileID,
            name: "Just Left",
            tabs: foreignCards
        )
        browser = BrowserStore(
            seed: SessionState.Seed(spaces: [own, foreign]),
            showing: own.id, tabs: firstTabs(of: [own, foreign]),
            browsingMode: .privateBrowsing
        )
        sidebarInteraction = BrowserSidebarInteractionState.connected(to: browser)
    }

    var ownSpace: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(
            spaceID: ownSpaceID,
            profileID: ownProfileID
        )
    }

    var foreignSpace: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(
            spaceID: foreignSpaceID,
            profileID: foreignProfileID
        )
    }

    /// A point in the leading half of the second card on show, so the drop
    /// belongs between the first two cards and nowhere else.
    var pointerInSecondOwnCard: CGPoint {
        let card = splitCardFrames(count: ownCardCount)[1]
        return CGPoint(x: card.minX + card.width / 4, y: card.midY)
    }

    /// Registers the content area as this Space's drop zone, then both Spaces'
    /// cards over it.
    func register(in state: BrowserSidebarReorderState) {
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .splitContent(ownSpace),
                frame: splitContentZone
            ),
            for: UUID()
        )
        state.register(
            row: BrowserSidebarReorderRow(
                id: .tab(joiner.id),
                space: ownSpace,
                section: currentSection,
                frame: splitJoinerRow
            ),
            owner: UUID()
        )

        for (tab, frame) in zip(ownCards, splitCardFrames(count: ownCardCount)) {
            state.register(
                splitCardFrame: frame,
                for: tab.id,
                in: ownSpace,
                owner: UUID()
            )
        }
        for (tab, frame) in zip(
            foreignCards,
            splitCardFrames(count: foreignCardCount)
        ) {
            state.register(
                splitCardFrame: frame,
                for: tab.id,
                in: foreignSpace,
                owner: UUID()
            )
        }
    }

    /// Lifts the tab out of its sidebar row and holds the pointer at `pointer`.
    func liftTheJoiner(
        in state: BrowserSidebarReorderState,
        to pointer: CGPoint
    ) {
        state.begin(
            item: .tab(
                BrowserTabDragItem(
                    tabID: joiner.id,
                    spaceID: ownSpaceID,
                    profileID: ownProfileID
                )
            ),
            section: currentSection,
            at: CGPoint(x: splitJoinerRow.midX, y: splitJoinerRow.midY)
        )
        state.update(pointer: pointer)
    }
}

private func makeSpace(
    id: UUID,
    profileID: UUID,
    name: String,
    tabs: [TabState.Seed]
) -> SpaceState.Seed {
    SpaceState.Seed(
        id: id,
        profileID: profileID,
        name: name,
        symbol: "rectangle.stack",
        accent: .indigo,
        folders: [],
        tabs: tabs
    )
}

/// Each Space shows its first tab, as the sidebar fixtures always have.
private func firstTabs(of spaces: [SpaceState.Seed]) -> [UUID: UUID] {
    var tabs: [UUID: UUID] = [:]
    for space in spaces {
        tabs[space.id] = space.tabs.first?.id
    }
    return tabs
}

private func makeTab(
    id: UUID,
    title: String,
    placement: TabPlacement
) -> TabState.Seed {
    TabState.Seed(
        id: id,
        title: title,
        url: URL(fileURLWithPath: "/crest-reorder-registry-scope/\(title)"),
        placement: placement,
        lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

private func uuid(_ finalByte: UInt8) -> UUID {
    UUID(
        uuid: (
            0x52, 0x45, 0x47, 0x49, 0x53, 0x54, 0x52, 0x59,
            0x53, 0x43, 0x4F, 0x50, 0x45, 0x00, 0x00, finalByte
        )
    )
}
