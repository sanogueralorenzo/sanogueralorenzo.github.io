import CoreGraphics
import Foundation
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserSidebarReorderPolicyTests: XCTestCase {
    /// A stage nothing ever came back for must not lock the strip for good.
    ///
    /// The stage is cleared by the promotion that lifts it, the drop that ends
    /// it, or a context menu taking the press. On a runtime without
    /// `onDragSessionUpdated` — the deployment target is iOS 26.1, and
    /// `BrowserMobileReorderSessionModifier` compiles away to its content below
    /// iOS 27 — a press that produces neither a session nor a menu is cleared by
    /// nothing at all. `hasLiftInFlight` then stayed true for the life of the
    /// process, and the Space pager reads exactly that: horizontal paging died
    /// in every sidebar on screen at once, in the floating sidebar and the
    /// full-screen tab viewer alike, with no lifted row to explain it.
    func testAStageNoDragClaimsStopsLockingTheSpaceStrip() async {
        let fixture = ReorderStagingFixture(
            stagedLiftExpiration: .milliseconds(10)
        )

        fixture.state.stage(item: fixture.item, section: fixture.section)
        XCTAssertTrue(lockedPager(fixture.state))

        await fixture.elapse(.milliseconds(10))

        XCTAssertFalse(
            fixture.state.hasLiftInFlight,
            "An unpromoted stage is written off rather than held for good."
        )
        XCTAssertFalse(
            lockedPager(fixture.state),
            "And the strip pages again once it is."
        )
        XCTAssertFalse(
            fixture.state.suppressesActivation,
            "No drag ever happened, so the row stays openable."
        )
    }

    /// What the pager itself computes, from the one state a touch lift touches.
    private func lockedPager(_ state: BrowserSidebarReorderState) -> Bool {
        BrowserSidebarInteractionState.ownsHorizontalAxis(
            hasSidebarLift: state.hasLiftInFlight,
            hasTabDrag: false,
            hasFolderDrag: false
        )
    }

    /// Everything one staged lift needs: a measured row to lift, a neighbour to
    /// aim at, and the section zone that answers for both.
    @MainActor
    private struct ReorderStagingFixture {
        let state: BrowserSidebarReorderState
        /// The time a stage's expiry waits on, moved only by `elapse`.
        let clock = ManualClock()
        let section = BrowserSidebarReorderSection.tabs(
            placement: .current,
            folderID: nil
        )
        let item: BrowserSidebarReorderItem
        let neighbourID: BrowserSidebarReorderItemID
        let draggedFrame = CGRect(x: 8, y: 110, width: 374, height: 44)
        let neighbourFrame = CGRect(x: 8, y: 154, width: 374, height: 44)

        var pointerOverNeighbour: CGPoint {
            CGPoint(x: neighbourFrame.midX, y: neighbourFrame.midY)
        }

        /// Lets every expiry already armed start its wait, moves the clock on
        /// by `duration`, then lets every expiry it woke run on the main actor
        /// before the test reads the state.
        func elapse(_ duration: Duration) async {
            for _ in 0..<8 { await Task.yield() }
            clock.advance(by: duration)
            for _ in 0..<8 { await Task.yield() }
        }

        init(
            stagedLiftExpiration: Duration = BrowserSidebarReorderState.stagedLiftExpiration
        ) {
            state = BrowserSidebarReorderState(
                stagedLiftExpiration: stagedLiftExpiration, clock: clock
            )
            let spaceID = UUID()
            let profileID = UUID()
            item = .tab(
                BrowserTabDragItem(
                    tabID: UUID(),
                    spaceID: spaceID,
                    profileID: profileID
                )
            )
            state.register(
                row: BrowserSidebarReorderRow(
                    id: item.id,
                    space: item.spaceAssignment,
                    section: section,
                    frame: draggedFrame
                ),
                owner: UUID()
            )
            neighbourID = .tab(UUID())
            state.register(
                row: BrowserSidebarReorderRow(
                    id: neighbourID,
                    space: item.spaceAssignment,
                    section: section,
                    frame: neighbourFrame
                ),
                owner: UUID()
            )
            state.register(
                zone: BrowserSidebarReorderZone(
                    target: .section(section),
                    frame: draggedFrame.union(neighbourFrame)
                        .insetBy(dx: -8, dy: -10)
                ),
                for: UUID()
            )
        }
    }

    // MARK: - A lift that starts on a pinned tile

    // MARK: - What an open folder says while a drop is aimed at it

    // MARK: - A lift carried onto the page

    /// Drag-to-split, from the touch shell's own three-piece contract: `.onDrag`
    /// stages, the first reported position promotes, and the position that
    /// promotes may be one the *page* reported rather than the sidebar.
    ///
    /// That last part is the whole of what iPadOS was missing. macOS streams its
    /// lift from a `DragGesture` that keeps reporting wherever the pointer goes,
    /// so the page needs no feed of its own; a touch lift hears only from the
    /// drop interactions it passes over, and there was none over the content
    /// area at all — a finger that left the sidebar went dark, and the cards on
    /// show could not be joined.
    func testAPositionReportedOverThePagePromotesTheLiftAndResolvesACardSlot() {
        let fixture = PadContentAreaFixture(cardCount: 2)
        fixture.register()

        fixture.stageTheLift()
        XCTAssertFalse(
            fixture.state.isDragging,
            "Staging alone lifts nothing, on the page as anywhere else."
        )

        fixture.state.update(pointer: fixture.pointInLeadingHalf(ofCard: 1))

        XCTAssertTrue(
            fixture.state.isDragging,
            "The content area's feed reports positions like any other, so the "
                + "sample that arrives from it must promote the staged lift."
        )
        XCTAssertEqual(
            fixture.state.resolvedTarget?.kind,
            .splitInsert(assignment: fixture.assignment, index: 1),
            "Past the first card and short of the second's midpoint is the "
                + "seam between them."
        )
        XCTAssertEqual(fixture.state.liftTargetShape, .webpageCard)
        XCTAssertTrue(fixture.state.hasEnteredSplitContent)
    }

    /// A sidebar the reader has undocked is drawn *on top of* the page, so the
    /// content zone spans the whole window and every sidebar run overlaps it.
    /// The runs still win, including the seams between them — which is the only
    /// way a narrow iPad's lists stay reachable while the page offers itself.
    func testAFloatingSidebarDrawnOverThePageKeepsItsOwnRuns() {
        let fixture = PadContentAreaFixture(
            cardCount: 2,
            sidebarIsFloating: true
        )
        fixture.register()

        fixture.stageTheLift()

        fixture.state.update(pointer: fixture.pointInTheOpenList)
        XCTAssertEqual(
            fixture.state.resolvedTarget?.section,
            fixture.section,
            "A run under the finger outranks the page behind it."
        )

        fixture.state.update(pointer: fixture.pointInLeadingHalf(ofCard: 1))
        XCTAssertEqual(
            fixture.state.resolvedTarget?.kind,
            .splitInsert(assignment: fixture.assignment, index: 1),
            "Past the floating card there is nothing else to outrank it."
        )
    }

    /// The release, end to end: what the touch shell's drop delegate does when
    /// the finger lets go over the page, through the shared commit.
    ///
    /// A lone tab on show and a tab dropped on its trailing half is the gesture
    /// that creates a split, and the session has to come out of it holding a
    /// group of the two in that order.
    func testAReleaseOverTheLoneCardCommitsTheSplitTheDragPromised() throws {
        let fixture = PadContentAreaFixture(cardCount: 1)
        fixture.register()

        fixture.stageTheLift()
        fixture.state.update(pointer: fixture.pointInTrailingHalf(ofCard: 0))

        let drop = try XCTUnwrap(fixture.state.end())
        fixture.commit(drop)

        let space = try XCTUnwrap(fixture.browser.shownSpace)
        let groupID = try XCTUnwrap(space.shownSplit(containing: fixture.cards[0].id))
        XCTAssertEqual(
            space.splitMembers(of: groupID).map(\.id),
            [fixture.cards[0].id, fixture.joiner.id],
            "Dropped on the trailing half, the carried tab lands behind the "
                + "card that was already there."
        )
        XCTAssertFalse(
            fixture.state.hasEnteredSplitContent,
            "The drop ends the drag, so the layout latch it opened stands down."
        )
    }

    /// The iPad content area, measured the way the shell lays it out: the detail
    /// column beside a docked sidebar — or the whole window with one floating
    /// over it — the page insets `BrowserSplitColumnsView` applies, and the cards
    /// `BrowserSplitColumnLayout` shares the remainder between.
    @MainActor
    private struct PadContentAreaFixture {
        let sidebarInteraction: BrowserSidebarInteractionState
        let browser: BrowserStore
        let cards: [TabState.Seed]
        let joiner: TabState.Seed
        let section = BrowserSidebarReorderSection.tabs(
            placement: .current,
            folderID: nil
        )

        private let sidebarIsFloating: Bool
        private let spaceID = padUUID(0x01)
        private let profileID = padUUID(0x02)

        /// A 13-inch iPad in landscape, with the sidebar width the shell defaults
        /// to for that width.
        private static let windowSize = CGSize(width: 1_210, height: 834)
        private static let sidebarWidth: CGFloat = 280
        private static let joinerRow = CGRect(x: 12, y: 300, width: 256, height: 44)

        init(cardCount: Int, sidebarIsFloating: Bool = false) {
            self.sidebarIsFloating = sidebarIsFloating
            cards = (0..<cardCount).map { index in
                padTab(
                    id: padUUID(UInt8(0x10 + index)),
                    title: "Card \(index)"
                )
            }
            joiner = padTab(
                id: padUUID(0x30),
                title: "Joiner"
            )
            let space = SpaceState.Seed(
                id: spaceID,
                profileID: profileID,
                name: "Reading",
                folders: [],
                tabs: cards + [joiner]
            )
            browser = BrowserStore(
                seed: SessionState.Seed(spaces: [space]),
                showing: space.id, tabs: [space.id: cards.first?.id ?? joiner.id],
                browsingMode: .privateBrowsing
            )
            sidebarInteraction = BrowserSidebarInteractionState.connected(to: browser)
        }

        var state: BrowserSidebarReorderState { sidebarInteraction.sidebarReorderState }

        var assignment: BrowserSpaceRuntimeAssignment {
            BrowserSpaceRuntimeAssignment(spaceID: spaceID, profileID: profileID)
        }

        /// What `MobileRegularPageSurface` offers as a zone: the whole detail
        /// column, insets included. A floating sidebar is drawn over the page, so
        /// the detail column is then the whole window.
        var contentZone: CGRect {
            sidebarIsFloating
                ? CGRect(origin: .zero, size: Self.windowSize)
                : CGRect(
                    x: Self.sidebarWidth,
                    y: 0,
                    width: Self.windowSize.width - Self.sidebarWidth,
                    height: Self.windowSize.height
                )
        }

        /// The run the sidebar puts its open list in, which a floating card draws
        /// on top of the page.
        var sidebarZone: CGRect {
            CGRect(x: 8, y: 260, width: Self.sidebarWidth - 16, height: 420)
        }

        var pointInTheOpenList: CGPoint {
            CGPoint(x: sidebarZone.midX, y: sidebarZone.midY)
        }

        func pointInLeadingHalf(ofCard index: Int) -> CGPoint {
            let card = cardFrames[index]
            return CGPoint(x: card.minX + card.width / 4, y: card.midY)
        }

        func pointInTrailingHalf(ofCard index: Int) -> CGPoint {
            let card = cardFrames[index]
            return CGPoint(x: card.maxX - card.width / 4, y: card.midY)
        }

        /// Where the columns row puts each card: the zone less the page insets,
        /// shared into equal columns with the row's own gap between them.
        var cardFrames: [CGRect] {
            let insets = BrowserChromeLayout.pageFrameInsets(
                adjoinsLeadingSidebar: !sidebarIsFloating
            )
            let row = CGRect(
                x: contentZone.minX + insets.leading,
                y: contentZone.minY + insets.top,
                width: contentZone.width - insets.leading - insets.trailing,
                height: contentZone.height - insets.top - insets.bottom
            )
            let widths = BrowserSplitColumnLayout.widths(
                containerWidth: row.width,
                fractions: BrowserSplitColumnLayout.seedFractions(
                    persisted: nil,
                    memberCount: cards.count
                )
            )
            var leading = row.minX
            return widths.map { width in
                defer {
                    leading += width + BrowserSplitLayoutMetrics.interCardGap
                }
                return CGRect(
                    x: leading,
                    y: row.minY,
                    width: width,
                    height: row.height
                )
            }
        }

        /// Everything the iPad shell registers once this lands: the sidebar's own
        /// run, the content area as a zone, and one frame per presented card.
        func register() {
            registerSidebar()
            registerZone()
            registerCards()
        }

        /// Stages the lift as the sidebar does, asking the core where it may
        /// land.
        func stageTheLift() {
            state.stage(item: liftItem, section: section, plan: reorder.plan(for: liftItem))
        }

        func commit(_ drop: BrowserSidebarReorderDrop) {
            reorder.commit(drop)
        }

        private var reorder: BrowserSidebarReorderContext {
            BrowserSidebarReorderContext(
                browser: browser,
                state: state
            )
        }

        private var liftItem: BrowserSidebarReorderItem {
            .tab(
                BrowserTabDragItem(
                    tabID: joiner.id,
                    spaceID: spaceID,
                    profileID: profileID
                )
            )
        }

        private func registerSidebar() {
            state.register(
                row: BrowserSidebarReorderRow(
                    id: liftItem.id,
                    space: assignment,
                    section: section,
                    frame: Self.joinerRow
                ),
                owner: UUID()
            )
            state.register(
                zone: BrowserSidebarReorderZone(
                    target: .section(section),
                    frame: sidebarZone
                ),
                for: UUID()
            )
        }

        private func registerZone() {
            state.register(
                zone: BrowserSidebarReorderZone(
                    target: .splitContent(assignment),
                    frame: contentZone
                ),
                for: UUID()
            )
        }

        private func registerCards() {
            for (card, frame) in zip(cards, cardFrames) {
                state.register(
                    splitCardFrame: frame,
                    for: card.id,
                    in: assignment,
                    owner: UUID()
                )
            }
        }
    }

}

/// A clock whose time moves only when a test moves it, so a wait ends at a
/// known point rather than after however long a loaded machine takes.
private final class ManualClock: Clock, @unchecked Sendable {
    // MARK: - Types

    struct Instant: InstantProtocol {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    // MARK: - Variables

    private let lock = NSLock()
    private var current = Instant(offset: .zero)
    private var sleepers: [(deadline: Instant, continuation: CheckedContinuation<Void, Never>)] = []

    var now: Instant { lock.withLock { current } }
    var minimumResolution: Duration { .zero }

    // MARK: - Actions - Time

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        await withCheckedContinuation { continuation in
            let isDue = lock.withLock {
                guard deadline > current else { return true }
                sleepers.append((deadline, continuation))
                return false
            }
            if isDue { continuation.resume() }
        }
    }

    /// Moves time on by `duration` and wakes every wait that ends by then.
    func advance(by duration: Duration) {
        let woken = lock.withLock {
            current = current.advanced(by: duration)
            let due = sleepers.filter { $0.deadline <= current }
            sleepers.removeAll { $0.deadline <= current }
            return due.map(\.continuation)
        }
        for continuation in woken { continuation.resume() }
    }
}
