import AppKit
import XCTest

import struct SwiftUI.Color

@testable import Crest

@MainActor
final class BrowserInteractionModelTests: XCTestCase {

    func testSpaceIdentityAndOrderingRemainStableAcrossEdits() throws {
        let browser = BrowserStore(seed: .preview)
        let profilesBySpaceID = Dictionary(
            uniqueKeysWithValues: browser.spaceModels.map {
                ($0.id, $0.profileID)
            }
        )
        browser.addSpace()
        let movedID = try XCTUnwrap(browser.spaceModels.first?.id)

        browser.moveSpaces(
            from: IndexSet(integer: browser.spaceModels.startIndex),
            to: browser.spaceModels.endIndex
        )
        browser.updateSpaceIdentity(
            movedID,
            name: "  Research  ",
            symbol: "graduationcap.fill",
            accent: .teal
        )

        let session = browser.sessionSeed
        let moved = try XCTUnwrap(session.spaces.last)
        XCTAssertEqual(moved.id, movedID)
        XCTAssertEqual(moved.settings.name, "Research")
        XCTAssertEqual(moved.settings.symbol, "graduationcap.fill")
        XCTAssertEqual(moved.settings.accent, .teal)
        for (spaceID, profileID) in profilesBySpaceID {
            XCTAssertEqual(session.space(id: spaceID)?.profileID, profileID)
        }
        XCTAssertEqual(browser.selectedSpaceID, session.spaces.dropLast().last?.id)
    }

    func testRowInsertionLowerHalfResolvesBeforeTheActualFollowingTab() throws {
        let first = TabState.Seed(title: "First", url: URL(string: "https://example.com/1"), placement: .current)
        let second = TabState.Seed(title: "Second", url: URL(string: "https://example.com/2"), placement: .current)
        let third = TabState.Seed(title: "Third", url: URL(string: "https://example.com/3"), placement: .current)
        var space = SpaceState.Seed.blank(number: 1)
        space.tabs = [first, second, third]
        let browser = BrowserStore(seed: SessionState.Seed(spaces: [space], defaultSpaceID: space.id))
        let model = try XCTUnwrap(browser.spaceModel(space.id))
        let items = BrowserSidebarListItem.items(
            of: model.sidebar.section(.current), in: model, namesFollowingTabs: true)
        let following = Dictionary(
            uniqueKeysWithValues: items.compactMap { item in
                item.id.tabID.map { ($0, item.followingTabID) }
            })

        XCTAssertEqual(following[first.id], second.id)
        XCTAssertEqual(following[second.id], third.id)
        XCTAssertNil(following[third.id] ?? nil)
        XCTAssertEqual(items.map(\.id), [.tab(first.id), .tab(second.id), .tab(third.id)])
    }

    func testMobileDragLifecycleUsesTheNativeCompletionOnlyWhereItExists() {
        XCTAssertFalse(
            BrowserTabDragSessionLifecyclePhase.usesNativeCompletion(
                runtimeMajorVersion: 26
            )
        )
        XCTAssertTrue(
            BrowserTabDragSessionLifecyclePhase.usesNativeCompletion(
                runtimeMajorVersion: 27
            )
        )
        XCTAssertFalse(
            BrowserTabDragSessionLifecyclePhase.active.endsSession
        )
        XCTAssertTrue(
            BrowserTabDragSessionLifecyclePhase.ended.endsSession
        )
        XCTAssertTrue(
            BrowserTabDragSessionLifecyclePhase.dataTransferCompleted.endsSession
        )
    }

    func testFallbackTouchReleaseClearsAHeldTabAfterDropResolution() async {
        let tabID = UUID()
        let dragState = BrowserTabDragState()
        let item = BrowserTabDragItem(
            tabID: tabID,
            spaceID: UUID(),
            profileID: UUID()
        )

        dragState.begin(item: item, placement: .current)
        dragState.endAfterTouchRelease()

        XCTAssertTrue(dragState.isDragging(item))
        try? await Task.sleep(
            for: BrowserTabDragState.releaseCleanupDelay * 2
        )
        XCTAssertFalse(dragState.isDragging(item))
        XCTAssertNil(dragState.dropLocation)
    }

    func testFallbackTouchReleaseClearsAHeldFolderAfterDropResolution() async {
        let folderID = UUID()
        let dragState = BrowserFolderDragState()
        let item = BrowserFolderDragItem(
            folderID: folderID,
            spaceID: UUID(),
            profileID: UUID()
        )

        dragState.begin(item: item)
        dragState.endAfterTouchRelease()

        XCTAssertTrue(dragState.isDragging(item))
        try? await Task.sleep(
            for: BrowserTabDragState.releaseCleanupDelay * 2
        )
        XCTAssertFalse(dragState.isDragging(item))
        XCTAssertNil(dragState.dropLocation)
    }

    func testOpeningATabContextMenuCancelsItsFalseDragLift() {
        let tabID = UUID()
        let dragState = BrowserTabDragState()
        let firstItem = BrowserTabDragItem(
            tabID: tabID,
            spaceID: UUID(),
            profileID: UUID()
        )

        dragState.begin(item: firstItem, placement: .current)
        dragState.contextMenuDidOpen(for: firstItem.runtimeAssignment)
        let secondItem = BrowserTabDragItem(
            tabID: tabID,
            spaceID: UUID(),
            profileID: UUID()
        )
        dragState.begin(item: secondItem, placement: .current)
        dragState.contextMenuDidClose(for: secondItem.runtimeAssignment)

        XCTAssertFalse(dragState.isDragging(secondItem))
        XCTAssertNil(dragState.dropLocation)
    }

    func testOpeningAFolderContextMenuCancelsItsFalseDragLift() {
        let folderID = UUID()
        let dragState = BrowserFolderDragState()
        let firstItem = BrowserFolderDragItem(
            folderID: folderID,
            spaceID: UUID(),
            profileID: UUID()
        )

        dragState.begin(item: firstItem)
        dragState.contextMenuDidOpen(for: firstItem)
        let secondItem = BrowserFolderDragItem(
            folderID: folderID,
            spaceID: UUID(),
            profileID: UUID()
        )
        dragState.begin(item: secondItem)
        dragState.contextMenuDidClose(for: secondItem)

        XCTAssertFalse(dragState.isDragging(secondItem))
        XCTAssertNil(dragState.dropLocation)
    }

    // MARK: - In-view sidebar reorder geometry

    private func reorderRow(
        _ id: BrowserSidebarReorderItemID,
        in space: BrowserSpaceRuntimeAssignment,
        section: BrowserSidebarReorderSection,
        _ frame: CGRect
    ) -> BrowserSidebarReorderRow {
        BrowserSidebarReorderRow(
            id: id,
            space: space,
            section: section,
            frame: frame
        )
    }

    // MARK: - Cross-section reorder feedback

    /// Cross-section drops retain the exact destination section and insertion index.
    func testCrossSectionDropsResolveTheDestinationSectionAndIndex() {
        let sidebar = StackedSidebar()
        let pinned = BrowserSidebarReorderSection.tabs(
            placement: .pinned,
            folderID: nil
        )
        let saved = BrowserSidebarReorderSection.tabs(
            placement: .saved,
            folderID: nil
        )
        let current = BrowserSidebarReorderSection.tabs(
            placement: .current,
            folderID: nil
        )

        // Current into the saved list, short of the second row's midpoint.
        var outcome = sidebar.crossing(
            lift: sidebar.current[0],
            from: current,
            at: CGPoint(x: 100, y: 270),
            to: CGPoint(x: 100, y: 150)
        )
        XCTAssertEqual(
            outcome,
            .insert(section: saved, beforeID: sidebar.saved[1], index: 1)
        )

        // Saved back into the current list.
        outcome = sidebar.crossing(
            lift: sidebar.saved[0],
            from: saved,
            at: CGPoint(x: 100, y: 110),
            to: CGPoint(x: 100, y: 290)
        )
        XCTAssertEqual(
            outcome,
            .insert(section: current, beforeID: sidebar.current[1], index: 1)
        )

        // Current into Pinned: two columns become three; the drop uses the
        // final grid width rather than shifting a fixed grid off its edge.
        outcome = sidebar.crossing(
            lift: sidebar.current[0],
            from: current,
            at: CGPoint(x: 100, y: 270),
            to: CGPoint(x: 50, y: 20)
        )
        XCTAssertEqual(
            outcome,
            .insert(section: pinned, beforeID: sidebar.pinned[1], index: 1)
        )

        // Pinned into the saved list.
        outcome = sidebar.crossing(
            lift: sidebar.pinned[0],
            from: pinned,
            at: CGPoint(x: 40, y: 20),
            to: CGPoint(x: 100, y: 190)
        )
        XCTAssertEqual(
            outcome,
            .insert(section: saved, beforeID: sidebar.saved[2], index: 2)
        )

        // Saved past the last pinned cell resolves to the end of that section.
        outcome = sidebar.crossing(
            lift: sidebar.saved[0],
            from: saved,
            at: CGPoint(x: 100, y: 110),
            to: CGPoint(x: 190, y: 20)
        )
        XCTAssertEqual(
            outcome,
            .insert(section: pinned, beforeID: nil, index: 2)
        )

        // Reordering within one section resolves after excluding the lifted row.
        outcome = sidebar.crossing(
            lift: sidebar.saved[0],
            from: saved,
            at: CGPoint(x: 100, y: 110),
            to: CGPoint(x: 100, y: 190)
        )
        XCTAssertEqual(
            outcome,
            .insert(section: saved, beforeID: sidebar.saved[2], index: 1)
        )

    }

    /// A folder's tabs are their own section, measured inside the saved list
    /// that holds the folder. A tab arriving from the current list has to open
    /// the gap among the folder's rows, not in the list behind them.
    func testALiftCrossingIntoAFolderScopedSectionResolvesItsRows() {
        let state = BrowserSidebarReorderState()
        let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: UUID(),
            profileID: UUID()
        )
        let folderID = UUID()
        let folderSection = BrowserSidebarReorderSection.tabs(
            placement: .saved,
            folderID: folderID
        )
        let filed = (0..<2).map { _ in BrowserSidebarReorderItemID.tab(UUID()) }
        let unfiled = BrowserSidebarReorderItemID.tab(UUID())
        let lifted = BrowserSidebarReorderItemID.tab(UUID())

        for (index, id) in filed.enumerated() {
            state.register(
                row: reorderRow(
                    id,
                    in: assignment,
                    section: folderSection,
                    CGRect(
                        x: 0,
                        y: 100 + CGFloat(index) * 40,
                        width: 200,
                        height: 40
                    )
                ),
                owner: UUID()
            )
        }
        state.register(
            row: reorderRow(
                unfiled,
                in: assignment,
                section: .tabs(placement: .saved, folderID: nil),
                CGRect(x: 0, y: 190, width: 200, height: 40)
            ),
            owner: UUID()
        )
        state.register(
            row: reorderRow(
                lifted,
                in: assignment,
                section: .tabs(placement: .current, folderID: nil),
                CGRect(x: 0, y: 260, width: 200, height: 40)
            ),
            owner: UUID()
        )
        // The folder group's own run sits inside the saved list's zone.
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .section(.tabs(placement: .saved, folderID: nil)),
                frame: CGRect(x: 0, y: 95, width: 200, height: 140)
            ),
            for: UUID()
        )
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .section(folderSection),
                frame: CGRect(x: 0, y: 95, width: 200, height: 90)
            ),
            for: UUID()
        )

        state.begin(
            item: .tab(
                BrowserTabDragItem(
                    tabID: lifted.tabID ?? UUID(),
                    spaceID: assignment.spaceID,
                    profileID: assignment.profileID
                )
            ),
            section: .tabs(placement: .current, folderID: nil),
            at: CGPoint(x: 100, y: 270)
        )
        state.update(pointer: CGPoint(x: 100, y: 150))

        XCTAssertEqual(
            state.resolvedTarget?.kind,
            .insert(section: folderSection, beforeID: filed[1], index: 1)
        )

        state.cancel()
    }

    /// A row that changes section is an arriving view in the section it lands in
    /// and a departing view in the one it left, and SwiftUI runs the departing
    /// view's `onDisappear` after the arriving one has measured itself. Keyed by
    /// item alone, that late removal wipes the registration the arrival just
    /// made: the row drops out of its new section's geometry, nothing displaces
    /// around it, and every later drop aims straight past it.
    func testARowMovingBetweenSectionsKeepsTheRegistrationItsArrivalMade() {
        let sidebar = StackedSidebar()

        // The saved list's middle row got there by being dragged out of the
        // current list: its new row measured itself, then its old row left.
        let arrival = UUID()
        let departure = UUID()
        sidebar.state.register(
            row: reorderRow(
                sidebar.saved[1],
                in: sidebar.assignment,
                section: .tabs(placement: .saved, folderID: nil),
                CGRect(x: 0, y: 140, width: 200, height: 40)
            ),
            owner: arrival
        )
        sidebar.state.removeRow(sidebar.saved[1], owner: departure)

        let outcome = sidebar.crossing(
            lift: sidebar.current[0],
            from: .tabs(placement: .current, folderID: nil),
            at: CGPoint(x: 100, y: 270),
            to: CGPoint(x: 100, y: 150)
        )

        XCTAssertEqual(
            outcome,
            .insert(
                section: .tabs(placement: .saved, folderID: nil),
                beforeID: sidebar.saved[1],
                index: 1
            )
        )

    }

    /// The three macOS sidebar sections at fixed geometry: a two-cell pinned
    /// grid on top, a three-row saved list under it, and a two-row current list
    /// at the bottom, each wrapped in the zone its section registers.
    @MainActor
    private struct StackedSidebar {
        let state = BrowserSidebarReorderState()
        let pinned = (0..<2).map { _ in BrowserSidebarReorderItemID.tab(UUID()) }
        let saved = (0..<3).map { _ in BrowserSidebarReorderItemID.tab(UUID()) }
        let current = (0..<2).map { _ in BrowserSidebarReorderItemID.tab(UUID()) }

        /// The Space every row here belongs to. Readable from outside because a
        /// row registration has to say which Space's run it stands in.
        let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: UUID(),
            profileID: UUID()
        )

        init() {
            register(pinned, in: .tabs(placement: .pinned, folderID: nil)) {
                CGRect(x: CGFloat($0) * 104, y: 0, width: 96, height: 47)
            }
            register(saved, in: .tabs(placement: .saved, folderID: nil)) {
                CGRect(x: 0, y: 100 + CGFloat($0) * 40, width: 200, height: 40)
            }
            register(current, in: .tabs(placement: .current, folderID: nil)) {
                CGRect(x: 0, y: 260 + CGFloat($0) * 40, width: 200, height: 40)
            }
            register(
                .tabs(placement: .pinned, folderID: nil),
                over: CGRect(x: 0, y: 0, width: 200, height: 47)
            )
            register(
                .tabs(placement: .saved, folderID: nil),
                over: CGRect(x: 0, y: 95, width: 200, height: 130)
            )
            // The saved list registers a folder run over the same frame.
            register(
                .folders(parentID: nil),
                over: CGRect(x: 0, y: 95, width: 200, height: 130)
            )
            register(
                .tabs(placement: .current, folderID: nil),
                over: CGRect(x: 0, y: 255, width: 200, height: 90)
            )
        }

        /// Resolve a destination while the pointer is held, then end the lift.
        func crossing(
            lift id: BrowserSidebarReorderItemID,
            from section: BrowserSidebarReorderSection,
            at liftPoint: CGPoint,
            to pointer: CGPoint
        ) -> BrowserSidebarReorderTarget.Kind? {
            state.begin(item: item(id), section: section, at: liftPoint)
            state.update(pointer: pointer)
            defer { state.cancel() }
            return state.resolvedTarget?.kind
        }

        func item(
            _ id: BrowserSidebarReorderItemID
        ) -> BrowserSidebarReorderItem {
            .tab(
                BrowserTabDragItem(
                    tabID: id.tabID ?? UUID(),
                    spaceID: assignment.spaceID,
                    profileID: assignment.profileID
                )
            )
        }

        private func register(
            _ ids: [BrowserSidebarReorderItemID],
            in section: BrowserSidebarReorderSection,
            frame: (Int) -> CGRect
        ) {
            for (index, id) in ids.enumerated() {
                state.register(
                    row: BrowserSidebarReorderRow(
                        id: id,
                        space: assignment,
                        section: section,
                        frame: frame(index)
                    ),
                    owner: UUID()
                )
            }
        }

        private func register(
            _ section: BrowserSidebarReorderSection,
            over frame: CGRect
        ) {
            state.register(
                zone: BrowserSidebarReorderZone(
                    target: .section(section),
                    frame: frame
                ),
                for: UUID()
            )
        }
    }

    // MARK: - A folder that fills the saved list

    /// The live shape behind the report: pinned tiles on top, one folder holding
    /// every saved tab, no unfiled saved rows at all, and a current list below.
    /// A tab lifted out of the current list and held over the folder's rows has
    /// to open the gap among them.
    ///
    /// Run with and without the band the unfiled run keeps below the folder.
    /// Without it the saved list measures exactly what the folder group
    /// measures, which is the shape the report came from.
    func testAFolderHoldingEverySavedTabResolvesACurrentLift() {
        for unfiledBand in [CGFloat.zero, CrestSpacing.medium] {
            let sidebar = FolderHeldSavedSidebar(unfiledBand: unfiledBand)

            let outcome = sidebar.crossing(
                lift: sidebar.current[0],
                from: .tabs(placement: .current, folderID: nil),
                at: CGPoint(x: 100, y: 265),
                to: CGPoint(x: 100, y: 160)
            )

            XCTAssertEqual(
                outcome,
                .insert(
                    section: .tabs(
                        placement: .saved,
                        folderID: sidebar.folderID
                    ),
                    beforeID: sidebar.filed[1],
                    index: 1
                )
            )

        }
    }

    /// The live macOS shape behind the report: a two-cell pinned grid, a saved
    /// list whose only content is one folder group holding every saved tab, and
    /// a current list below. The saved list and the folder group measure the
    /// same rectangle, because the list is a `VStack(spacing: 0)` around that
    /// single group.
    @MainActor
    private struct FolderHeldSavedSidebar {
        let state = BrowserSidebarReorderState()
        let folderID = UUID()
        let filed = (0..<2).map { _ in BrowserSidebarReorderItemID.tab(UUID()) }
        let current = (0..<2).map { _ in BrowserSidebarReorderItemID.tab(UUID()) }

        /// Header row plus the two filed rows under it.
        private static let folderGroup = CGRect(
            x: 0,
            y: 95,
            width: 200,
            height: 120
        )
        /// The folder group plus whatever band the unfiled run keeps below it.
        /// At zero the saved list *is* the folder group, which is what the live
        /// sidebar measured when the report came in.
        private let savedList: CGRect

        private let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: UUID(),
            profileID: UUID()
        )

        init(unfiledBand: CGFloat = 0) {
            savedList = CGRect(
                x: Self.folderGroup.minX,
                y: Self.folderGroup.minY,
                width: Self.folderGroup.width,
                height: Self.folderGroup.height + unfiledBand
            )
            for (index, id) in filed.enumerated() {
                register(
                    id,
                    in: .tabs(placement: .saved, folderID: folderID),
                    at: CGRect(
                        x: 16,
                        y: 135 + CGFloat(index) * 40,
                        width: 184,
                        height: 40
                    )
                )
            }
            for (index, id) in current.enumerated() {
                register(
                    id,
                    in: .tabs(placement: .current, folderID: nil),
                    at: CGRect(
                        x: 0,
                        y: 255 + CGFloat(index) * 40,
                        width: 200,
                        height: 40
                    )
                )
            }
            // The saved list registers its own run and the folder run beside it,
            // and the folder group registers both of its runs over itself.
            register(.tabs(placement: .saved, folderID: nil), over: savedList)
            register(.folders(parentID: nil), over: savedList)
            register(
                .tabs(placement: .saved, folderID: folderID),
                over: Self.folderGroup
            )
            register(
                .folders(parentID: folderID),
                over: Self.folderGroup.divided(
                    atDistance: 40,
                    from: .minYEdge
                ).remainder
            )
            register(
                .tabs(placement: .current, folderID: nil),
                over: CGRect(x: 0, y: 245, width: 200, height: 90)
            )
        }

        func crossing(
            lift id: BrowserSidebarReorderItemID,
            from section: BrowserSidebarReorderSection,
            at liftPoint: CGPoint,
            to pointer: CGPoint
        ) -> BrowserSidebarReorderTarget.Kind? {
            state.begin(item: item(id), section: section, at: liftPoint)
            state.update(pointer: pointer)
            defer { state.cancel() }
            return state.resolvedTarget?.kind
        }

        func item(
            _ id: BrowserSidebarReorderItemID
        ) -> BrowserSidebarReorderItem {
            .tab(
                BrowserTabDragItem(
                    tabID: id.tabID ?? UUID(),
                    spaceID: assignment.spaceID,
                    profileID: assignment.profileID
                )
            )
        }

        private func register(
            _ id: BrowserSidebarReorderItemID,
            in section: BrowserSidebarReorderSection,
            at frame: CGRect
        ) {
            state.register(
                row: BrowserSidebarReorderRow(
                    id: id,
                    space: assignment,
                    section: section,
                    frame: frame
                ),
                owner: UUID()
            )
        }

        private func register(
            _ section: BrowserSidebarReorderSection,
            over frame: CGRect
        ) {
            state.register(
                zone: BrowserSidebarReorderZone(
                    target: .section(section),
                    frame: frame
                ),
                for: UUID()
            )
        }
    }

    /// Tabs and folders each reorder only among their own kind, so overlapping
    /// sections in a folder group cannot capture the wrong item.
    func testSectionsOnlyAcceptTheirOwnKindOfItem() {
        let tab = BrowserSidebarReorderItem.tab(
            BrowserTabDragItem(tabID: UUID(), spaceID: UUID(), profileID: UUID())
        )
        let folder = BrowserSidebarReorderItem.folder(
            BrowserFolderDragItem(
                folderID: UUID(),
                spaceID: UUID(),
                profileID: UUID()
            )
        )

        XCTAssertTrue(
            tab.isAccepted(by: .tabs(placement: .saved, folderID: nil))
        )
        XCTAssertFalse(
            tab.isAccepted(by: .folders(parentID: nil))
        )
        XCTAssertTrue(
            folder.isAccepted(by: .folders(parentID: nil))
        )
        XCTAssertFalse(
            folder.isAccepted(by: .tabs(placement: .pinned, folderID: nil))
        )
    }

    /// A split group is a run of tabs, so it reorders among tabs — but never into
    /// the pinned grid, because pinned tabs cannot be members.
    func testSplitGroupsAreAcceptedOnlyByNonPinnedTabSections() {
        let group = BrowserSidebarReorderItem.splitGroup(
            BrowserSplitGroupDragItem(
                groupID: UUID(),
                spaceID: UUID(),
                profileID: UUID(),
                memberTabIDs: [UUID(), UUID()]
            )
        )

        XCTAssertTrue(
            group.isAccepted(by: .tabs(placement: .current, folderID: nil))
        )
        XCTAssertTrue(
            group.isAccepted(by: .tabs(placement: .saved, folderID: UUID()))
        )
        XCTAssertFalse(
            group.isAccepted(by: .tabs(placement: .pinned, folderID: nil))
        )
        XCTAssertFalse(
            group.isAccepted(by: .folders(parentID: nil))
        )
    }

    /// Folder-nesting and Space zones outrank the sections behind them. When
    /// the core offers a group no drop into either, it must fall through to the
    /// section instead of resolving a target the lift cannot take.
    func testSplitGroupDragsFallThroughFolderAndSpaceZonesToTheSection() {
        let frame = CGRect(x: 0, y: 0, width: 200, height: 40)
        let point = CGPoint(x: 100, y: 20)
        let section = BrowserSidebarReorderSection.tabs(
            placement: .saved,
            folderID: nil
        )
        let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: UUID(),
            profileID: UUID()
        )
        let zones = [
            BrowserSidebarReorderZone(target: .section(section), frame: frame),
            BrowserSidebarReorderZone(target: .folder(UUID()), frame: frame),
            BrowserSidebarReorderZone(target: .space(assignment), frame: frame),
        ]
        let group = BrowserSidebarReorderItem.splitGroup(
            BrowserSplitGroupDragItem(
                groupID: UUID(),
                spaceID: assignment.spaceID,
                profileID: assignment.profileID,
                memberTabIDs: [UUID(), UUID()]
            )
        )
        let tab = BrowserSidebarReorderItem.tab(
            BrowserTabDragItem(
                tabID: UUID(),
                spaceID: assignment.spaceID,
                profileID: assignment.profileID
            )
        )

        let plan = BrowserSidebarLiftPlan(
            selection: TabSelection(tabIDs: [], folderIDs: [], memberTabIDs: []),
            targets: DropTargetList(
                refusal: nil, lists: [ListDropTarget(section: .saved, folderID: nil)], spaceIDs: [],
                split: nil, folderAroundTabIDs: []))

        XCTAssertEqual(
            BrowserSidebarReorderZone.aimed(
                at: point,
                in: zones,
                accepting: group,
                plan: plan
            )?
            .target,
            .section(section)
        )
        XCTAssertEqual(
            BrowserSidebarReorderZone.aimed(
                at: point,
                in: zones,
                accepting: tab
            )?
            .target,
            .space(assignment),
            "A tab still takes the most specific zone."
        )
    }

    /// iOS stages a group lift from `.onDrag`, which runs at the press. Nothing
    /// may be lifted until the drop delegate reports a position: a press
    /// released without pulling produces no session, and a stage that lifted
    /// eagerly would hide the row with nothing in flight to put it back.
    func testAStagedSplitGroupLiftIsInertUntilADropPositionArrives() {
        let state = BrowserSidebarReorderState()
        let section = BrowserSidebarReorderSection.tabs(
            placement: .current,
            folderID: nil
        )
        let groupID = UUID()
        let item = BrowserSidebarReorderItem.splitGroup(
            BrowserSplitGroupDragItem(
                groupID: groupID,
                spaceID: UUID(),
                profileID: UUID(),
                memberTabIDs: [UUID(), UUID()]
            )
        )
        state.register(
            row: reorderRow(
                item.id,
                in: item.spaceAssignment,
                section: section,
                CGRect(x: 8, y: 110, width: 374, height: 120)
            ),
            owner: UUID()
        )
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .section(section),
                frame: CGRect(x: 0, y: 100, width: 390, height: 300)
            ),
            for: UUID()
        )

        state.stage(item: item, section: section)
        XCTAssertFalse(state.isDragging)
        XCTAssertFalse(state.isLifted(.splitGroup(groupID)))
        XCTAssertFalse(state.suppressesActivation)

        // The first tracked position is the proof a drag is genuinely in
        // flight, and it promotes the stage without any extra call site.
        state.update(pointer: CGPoint(x: 195, y: 150))
        XCTAssertTrue(state.isDragging)
        XCTAssertTrue(state.isLifted(.splitGroup(groupID)))
        state.cancel()
    }

    /// A staged lift whose session ends away from the sidebar is cleared by the
    /// mobile session modifier. Nothing may resurrect it afterwards, or the row
    /// stays invisible and untappable until the app is relaunched.
    func testACancelledSplitGroupStageCannotBePromotedLater() {
        let state = BrowserSidebarReorderState()
        let section = BrowserSidebarReorderSection.tabs(
            placement: .current,
            folderID: nil
        )
        let item = BrowserSidebarReorderItem.splitGroup(
            BrowserSplitGroupDragItem(
                groupID: UUID(),
                spaceID: UUID(),
                profileID: UUID(),
                memberTabIDs: [UUID(), UUID()]
            )
        )

        state.stage(item: item, section: section)
        state.cancel()

        state.update(pointer: CGPoint(x: 195, y: 150))
        XCTAssertFalse(state.isDragging)
        XCTAssertNil(state.end())
    }

    func testFolderDragUsesSavedInsertionLocationsAndCannotEnterPinnedTabs() {
        let folderID = UUID()
        let siblingID = UUID()
        let spaceID = UUID()
        let dragState = BrowserFolderDragState()
        let item = BrowserFolderDragItem(
            folderID: folderID,
            spaceID: spaceID,
            profileID: UUID()
        )
        let location = BrowserFolderDropLocation(
            parentID: nil,
            beforeSiblingID: siblingID
        )

        dragState.begin(item: item)
        XCTAssertTrue(dragState.isDragging(item))
        XCTAssertTrue(dragState.enter(location))
        XCTAssertEqual(dragState.dropLocation, location)

        dragState.end()
        XCTAssertNil(dragState.item)
        XCTAssertNil(dragState.dropLocation)
    }

    func testDraggingIntoAnotherSpacesSectionReownsTheTabAndContinuesTheLiveDrag() throws {
        let browser = BrowserStore.preview()
        let source = try XCTUnwrap(browser.spaceModels.first)
        let destination = try XCTUnwrap(browser.spaceModels.last)
        let tab = try XCTUnwrap(source.currentTabs.first)
        let item = BrowserTabDragItem(
            tabID: tab.id,
            spaceID: source.id,
            profileID: source.profileID
        )
        let sidebarInteraction = BrowserSidebarInteractionState.connected(to: browser)
        let token = sidebarInteraction.tabDragState.begin(item: item, placement: tab.placement)

        browser.selectSpace(destination.id)
        XCTAssertTrue(
            browser.moveTab(
                item,
                to: .saved,
                matching: BrowserSpaceRuntimeAssignment(space: destination)
            )
        )

        XCTAssertFalse(try XCTUnwrap(browser.spaceModel(source.id)).tabs.contains(tab.id))
        let moved = try XCTUnwrap(
            browser.spaceModel(destination.id)?.tabs.models.first(where: { $0.id == tab.id })
        )
        XCTAssertEqual(moved.placement, .saved)
        XCTAssertEqual(browser.shownTab?.id, tab.id)
        XCTAssertEqual(sidebarInteraction.tabDragState.item?.spaceID, destination.id)
        XCTAssertEqual(sidebarInteraction.tabDragState.currentPlacement, .current)
        XCTAssertEqual(sidebarInteraction.tabDragState.sessionToken, token)
    }

    func testNewTabFocusesAnAlreadySelectedStartPageWithoutAnOverlay() {
        let chrome = BrowserChromeState()
        let initialFocusRequest = chrome.startPageFocusRequest

        chrome.openNewTab(isStartPageSelected: true)

        XCTAssertNil(chrome.commandPaletteMode)
        XCTAssertNotEqual(chrome.startPageFocusRequest, initialFocusRequest)

        let focusedRequest = chrome.startPageFocusRequest
        chrome.openNewTab(isStartPageSelected: false)

        XCTAssertEqual(chrome.commandPaletteMode, .newTab)
        XCTAssertEqual(chrome.startPageFocusRequest, focusedRequest)
    }

    func testRootNewTabActionKeepsTheSelectedStartPageCohesive() throws {
        let browser = BrowserStore.hostingPages()
        let pages = BrowserPagePool(browser: browser)
        let chrome = BrowserChromeState()
        let model = BrowserRootModel(
            browser: browser,
            pages: pages,
            chrome: chrome,
            spaceAccess: BrowserSpaceAccessController(),
            windowState: nil,
            startupBehavior: .showStartPage,
            persistedSidebarWidth: BrowserChromeLayout.sidebarIdealWidth
        )
        // Launch shows the Space's first open tab, so show its Start Page.
        let startPage = try XCTUnwrap(browser.shownSpace?.currentTabs.first { $0.isStartPage })
        browser.selectTab(startPage.id)
        let selectedSpaceID = try XCTUnwrap(browser.shownSpace?.id)
        let selectedTabID = try XCTUnwrap(browser.shownTab?.id)
        XCTAssertEqual(selectedTabID, startPage.id)
        let currentTabs = try XCTUnwrap(browser.shownSpace?.currentTabs.map(\.id))
        let initialFocusRequest = chrome.startPageFocusRequest

        model.openNewTab()
        model.openNewTab()

        XCTAssertEqual(browser.shownSpace?.id, selectedSpaceID)
        XCTAssertEqual(browser.shownTab?.id, selectedTabID)
        XCTAssertEqual(browser.shownSpace?.currentTabs.map(\.id), currentTabs)
        XCTAssertNil(chrome.commandPaletteMode)
        XCTAssertEqual(chrome.startPageFocusRequest, initialFocusRequest + 2)
    }

    func testMiddleClickClosesOnlyCurrentTabsAndUnloadsSavedTabs() {
        XCTAssertEqual(BrowserTabMiddleClickAction(for: .current), .close)
        XCTAssertEqual(BrowserTabMiddleClickAction(for: .pinned), .unload)
        XCTAssertEqual(BrowserTabMiddleClickAction(for: .saved), .unload)
    }
}
