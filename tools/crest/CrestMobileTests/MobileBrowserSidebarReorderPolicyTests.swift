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
