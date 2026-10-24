import AppKit
import Observation
import XCTest

@testable import Crest

@MainActor
final class BrowserTabMultiSelectionTests: XCTestCase {
    func testCommandShiftAddsRangeFromCommandClickAndKeepsOtherSelections() {
        let ids = (0..<7).map { _ in UUID() }
        let selection = BrowserTabMultiSelection()
        selection.click(ids[0], units: ids.map { [$0] }, command: true)
        selection.click(ids[3], units: ids.map { [$0] }, command: true)
        selection.click(ids[5], units: ids.map { [$0] }, command: true, shift: true)
        XCTAssertEqual(selection.selectedIDs, Set([ids[0], ids[3], ids[4], ids[5]]))
        XCTAssertEqual(selection.anchorID, ids[3])
        selection.click(ids[4], units: ids.map { [$0] }, command: true, shift: true)
        XCTAssertEqual(selection.selectedIDs, Set([ids[0], ids[3], ids[4]]))
    }

    func testShiftRangeShrinksReversesAndTreatsSplitAsOneUnit() {
        let ids = (0..<6).map { _ in UUID() }
        let units = [[ids[0]], [ids[1], ids[2]], [ids[3]], [ids[4]], [ids[5]]]
        let selection = BrowserTabMultiSelection()
        selection.click(ids[3], units: units)
        selection.click(ids[5], units: units, shift: true)
        XCTAssertEqual(selection.selectedIDs, Set(ids[3...5]))
        selection.click(ids[2], units: units, shift: true)
        XCTAssertEqual(selection.selectedIDs, Set(ids[1...3]))
        selection.click(ids[1], units: units, command: true)
        XCTAssertEqual(selection.selectedIDs, [ids[3]])
    }

    func testShiftClickWithoutAnchorRangesFromTheActiveTab() {
        let ids = (0..<5).map { _ in UUID() }
        let units = ids.map { [BrowserSelectionItemID.tab($0)] }
        let selection = BrowserTabMultiSelection()
        selection.click(.tab(ids[4]), units: units, shift: true, activeItem: .tab(ids[1]))
        XCTAssertEqual(selection.selectedIDs, Set(ids[1...4]))
        XCTAssertEqual(selection.anchorID, ids[1])
        selection.click(.tab(ids[2]), units: units, shift: true, activeItem: .tab(ids[1]))
        XCTAssertEqual(selection.selectedIDs, Set(ids[1...2]))
    }

    func testShiftClickAnchorOutranksTheActiveTab() {
        let ids = (0..<5).map { _ in UUID() }
        let units = ids.map { [BrowserSelectionItemID.tab($0)] }
        let selection = BrowserTabMultiSelection()
        selection.click(.tab(ids[0]), units: units)
        selection.click(.tab(ids[3]), units: units, shift: true, activeItem: .tab(ids[1]))
        XCTAssertEqual(selection.selectedIDs, Set(ids[0...3]))
    }

    func testHiddenRowsArePrunedAndLostAnchorStartsANewRange() {
        let ids = (0..<4).map { _ in UUID() }
        let selection = BrowserTabMultiSelection()
        selection.click(ids[0], units: ids.map { [$0] }, command: true)
        selection.click(ids[3], units: ids.map { [$0] }, shift: true)
        selection.reconcile(units: [[ids[2]], [ids[3]]])
        XCTAssertEqual(selection.selectedIDs, Set(ids[2...3]))
        XCTAssertNil(selection.anchorID)
        selection.click(ids[2], units: [[ids[2]], [ids[3]]], shift: true)
        XCTAssertEqual(selection.selectedIDs, [ids[2]])
    }

    func testBatchFollowActivatesExactlyOneTabAndPersistsOnceInEitherBrowsingMode() throws {
        for mode in [BrowserBrowsingMode.standard, .privateBrowsing] {
            for follows in [false, true] {
                var session = makeSession(count: 3)
                session.spaces.append(SpaceState.Seed.blank(number: 2))
                let source = session.spaces[0]
                let destination = session.spaces[1]
                let preferences = BrowserLinkPreferenceStore()
                preferences.setBehavior(.followsMovedTabs, isOn: follows)
                let browser = BrowserStore(
                    seed: session,
                    showing: source.id, tabs: [source.id: source.tabs[0].id, destination.id: destination.tabs[0].id],
                    browsingMode: mode, linkPreferences: preferences)
                let ids = [source.tabs[2].id, source.tabs[0].id]
                let actions = BrowserTabBatchActions(browser: browser, spaceAccess: BrowserSpaceAccessController())
                let request = try XCTUnwrap(browser.capturedSelection(ids: ids))
                XCTAssertTrue(
                    actions.perform(
                        browser.moving(request, to: BrowserSpaceRuntimeAssignment(space: destination)), for: request))
                // They arrive in the order the sidebar lists them.
                XCTAssertEqual(
                    browser.spaceModels[1].tabs.models.suffix(2).map(\.id), [source.tabs[0].id, source.tabs[2].id])
                XCTAssertEqual(browser.selectedSpaceID, follows ? destination.id : source.id)
                XCTAssertEqual(
                    browser.selectedTabID(in: destination.id), follows ? source.tabs[0].id : destination.tabs[0].id)
                XCTAssertEqual(browser.consumeMovedTabActivation(), follows)
                XCTAssertFalse(browser.consumeMovedTabActivation())
                XCTAssertEqual(browser.isPrivateBrowsing, mode.isPrivate)
            }
        }
    }

    func testBatchDismissalDefersAllChangesAndRevalidatesAfterNativeConfirmation() throws {
        final class DeferredDismissal: BrowserPageDismissalAuthorizing {
            var assignments: [BrowserTabRuntimeAssignment] = []
            var operation: (@MainActor () -> Bool)?
            func performDismissal(
                of assignments: [BrowserTabRuntimeAssignment], in browser: BrowserStore,
                operation: @escaping @MainActor () -> Bool
            ) -> Bool {
                self.assignments = assignments
                self.operation = operation
                return false
            }
        }
        let session = makeSession(count: 3)
        let source = session.spaces[0]
        let browser = BrowserStore(seed: session)
        let opened = browser.sessionSeed
        let gate = DeferredDismissal()
        browser.family.pageDismissalAuthorizer = gate
        let actions = BrowserTabBatchActions(browser: browser, spaceAccess: BrowserSpaceAccessController())
        let request = try XCTUnwrap(browser.capturedSelection(ids: Array(source.tabs.prefix(2).map(\.id))))
        XCTAssertFalse(actions.perform(browser.closing(request), for: request))
        XCTAssertEqual(gate.assignments.map(\.tabID), request.ids)
        XCTAssertEqual(browser.sessionSeed, opened)
        gate.operation = nil  // Native cancellation never commits a subset.
        XCTAssertEqual(browser.sessionSeed, opened)
        XCTAssertFalse(actions.perform(browser.closing(request), for: request))
        XCTAssertTrue(browser.moveTab(source.tabs[0].id, to: .saved))
        let changed = browser.sessionSeed
        XCTAssertFalse(try XCTUnwrap(gate.operation)())
        XCTAssertEqual(browser.sessionSeed, changed)
        XCTAssertTrue(browser.moveTab(source.tabs[0].id, to: .current, before: source.tabs[1].id))
        XCTAssertFalse(actions.perform(browser.closing(request), for: request))
        XCTAssertTrue(try XCTUnwrap(gate.operation)())
        XCTAssertEqual(browser.spaceModels[0].archive.entries.count, 2)
        XCTAssertEqual(browser.spaceModels[0].tabs.models.map(\.id), [source.tabs[2].id])
    }

    func testDragCarriesCapturedBatchAndCancellationRestoresEveryLiftedRow() throws {
        let session = makeSession(count: 3)
        let source = session.spaces[0]
        let ids = [source.tabs[0].id, source.tabs[2].id]
        let browser = BrowserStore(seed: session)
        let opened = browser.sessionSeed
        let request = try XCTUnwrap(browser.capturedSelection(ids: ids))
        let item = BrowserSidebarReorderItem.tab(
            BrowserTabDragItem(
                tabID: ids[0], spaceID: source.id, profileID: source.profileID)
        ).selecting(request)
        let sidebarInteraction = BrowserSidebarInteractionState.connected(to: browser)
        let state = sidebarInteraction.sidebarReorderState
        state.begin(item: item, section: .tabs(placement: .current, folderID: nil), at: .zero)
        XCTAssertTrue(state.isLifted(.tab(ids[0])))
        XCTAssertTrue(state.isLifted(.tab(ids[1])))
        state.cancel()
        XCTAssertFalse(state.hasLiftInFlight)
        XCTAssertFalse(state.isLifted(.tab(ids[1])))
        XCTAssertEqual(browser.sessionSeed, opened)
        let forbidden = BrowserSidebarReorderTarget(
            kind: .insert(
                section: .tabs(placement: .pinned, folderID: nil), beforeID: nil, index: 0))
        // The core refuses pinning more than one tab, and the window says why.
        XCTAssertFalse(browser.sidebarDrop(item, on: forbidden.kind))
        XCTAssertEqual(
            browser.tabMultiSelection.message, Rejection.pinsOneTabAtATime(PinsOneTabAtATime()).placementExplanation)
        XCTAssertEqual(browser.sessionSeed, opened)
        let target = BrowserSidebarReorderTarget(
            kind: .insert(
                section: .tabs(placement: .saved, folderID: nil), beforeID: nil, index: 0))
        browser.tabMultiSelection.selectAll(units: [[source.tabs[1].id]])
        XCTAssertTrue(browser.sidebarDrop(item, on: target.kind))
        XCTAssertEqual(browser.shownSpace?.savedTabs.map(\.id), ids)
        XCTAssertEqual(browser.shownSpace?.currentTabs.map(\.id), [source.tabs[1].id])
    }

    func testMixedDragExcludesPinsAndPinOnlyDragStaysWithinItsSpace() throws {
        var session = makeSession(count: 4)
        session.spaces[0].tabs[0].placement = .pinned
        session.spaces[0].tabs[1].placement = .pinned
        let source = session.spaces[0]
        let ids = source.tabs.map(\.id)
        let selection = BrowserTabMultiSelection()
        selection.selectAll(units: ids.map { [$0] })
        let browser = BrowserStore(seed: session)
        let opened = browser.sessionSeed
        let mixed = try XCTUnwrap(browser.capturedSelection(ids: ids))
        let remaining = try XCTUnwrap(selection.releasePinnedTabs(from: mixed))
        let filtered = try XCTUnwrap(browser.capturedSelection(remaining))
        XCTAssertEqual(filtered.ids, Array(ids.suffix(2)))
        XCTAssertEqual(selection.selectedIDs, Set(ids.suffix(2)))
        XCTAssertEqual(selection.rejectedPinnedIDs, Set(ids.prefix(2)))
        let pins = try XCTUnwrap(browser.capturedSelection(ids: Array(ids.prefix(2))))
        let item = BrowserSidebarReorderItem.tab(
            BrowserTabDragItem(tabID: ids[0], spaceID: source.id, profileID: source.profileID)
        ).selecting(pins)
        let plan = try XCTUnwrap(browser.liftPlan(for: item))
        XCTAssertNotEqual(
            plan.verdict(
                on: BrowserSidebarReorderTarget(kind: .splitInsert(assignment: pins.assignment, index: 0))),
            .allowed)
        XCTAssertTrue(
            browser.sidebarDrop(
                item, on: .insert(section: .tabs(placement: .pinned, folderID: nil), beforeID: nil, index: 0)))
        XCTAssertTrue(
            browser.sidebarDrop(
                item, on: .insert(section: .tabs(placement: .saved, folderID: nil), beforeID: nil, index: 0)))
        XCTAssertEqual(browser.shownSpace?.savedTabs.map(\.id), pins.ids)
    }

    func testUnmountingScrollRowsPreservesLogicalSelectionUntilTabsAreRemoved() async throws {
        let session = makeSession(count: 3)
        let browser = BrowserStore(seed: session)
        let opened = browser.sessionSeed
        let interaction = BrowserSidebarInteractionState.connected(to: browser)
        let reorder = interaction.sidebarReorderState
        let space = session.spaces[0]
        let ids = space.tabs.map(\.id)
        let region = UUID()
        for (index, tab) in space.tabs.enumerated() {
            reorder.register(
                row: BrowserSidebarReorderRow(
                    id: .tab(tab.id), space: BrowserSpaceRuntimeAssignment(space: space),
                    section: .tabs(placement: tab.placement, folderID: nil),
                    frame: CGRect(x: 0, y: index * 40, width: 200, height: 40)),
                owner: UUID(), scrollRegionID: index == 0 ? nil : region)
        }
        browser.tabMultiSelection.selectAll(units: BrowserSidebarSelection.itemUnits(in: browser))
        XCTAssertEqual(browser.tabMultiSelection.selectedIDs, Set(ids))
        let reconciled = expectation(description: "Selection reconciles independently of mounted rows")
        withObservationTracking {
            _ = reorder.selectionRowsRevision
        } onChange: {
            Task { @MainActor in
                browser.tabMultiSelection.reconcile(
                    units: BrowserSidebarSelection.itemUnits(in: browser))
                reconciled.fulfill()
            }
        }

        reorder.removeScrollRegion(for: region)
        await fulfillment(of: [reconciled], timeout: 1)

        // Unmounting scroll content is not a model removal: lazy rows remain selectable.
        XCTAssertEqual(browser.tabMultiSelection.selectedIDs, Set(ids))
        XCTAssertEqual(browser.sessionSeed, opened)
        browser.closeTab(ids[2], matching: BrowserSpaceRuntimeAssignment(space: space))
        browser.tabMultiSelection.reconcile(units: BrowserSidebarSelection.itemUnits(in: browser))
        XCTAssertEqual(browser.tabMultiSelection.selectedIDs, Set(ids.prefix(2)))
    }

    func testSelectedAncestorCarriesDescendantsOnlyOnceAndEmptyFoldersRemainMovable() throws {
        var session = makeSession(count: 1)
        let parent = UUID()
        let child = UUID()
        session.spaces[0].folders = [
            FolderState.Seed(id: parent, title: "Parent"),
            FolderState.Seed(id: child, title: "Empty child", parentID: parent),
        ]
        let browser = makeBatchStore(session)
        let request = try XCTUnwrap(browser.capturedSelection([.folder(parent), .folder(child)]))
        XCTAssertEqual(request.rootItems, [.folder(parent)])
        XCTAssertTrue(request.ids.isEmpty)
        try browser.send(browser.filing(request, .current), for: request)
        session = browser.sessionSeed
        XCTAssertEqual(session.spaces[0].folders.first { $0.id == child }?.parentID, parent)
        XCTAssertTrue(session.spaces[0].folders.allSatisfy { $0.location == .current })
    }

    func testFolderAndWholeSplitCanBeWrappedWithoutFlatteningAndPinsAreExcluded() throws {
        var session = makeSession(count: 4)
        let ids = session.spaces[0].tabs.map(\.id)
        var created: UUID?
        session = try organized(session) { browser, space in
            created = browser.addFolder(title: "Empty", in: space.id)
            XCTAssertTrue(
                browser.addTabToSplit(
                    BrowserTabDragItem(tabID: ids[0], spaceID: space.id, profileID: space.profileID), joining: ids[1],
                    at: nil))
            XCTAssertTrue(browser.moveTab(ids[3], to: .pinned))
        }
        let folder = try XCTUnwrap(created)
        let items: [BrowserSelectionItemID] = [.folder(folder), .tab(ids[0]), .tab(ids[1]), .tab(ids[3])]
        let selection = BrowserTabMultiSelection()
        selection.selectAll(units: items.map { [$0] })
        let browser = makeBatchStore(session)
        let captured = try XCTUnwrap(browser.capturedSelection(items))
        let request = try XCTUnwrap(
            browser.capturedSelection(try XCTUnwrap(selection.releasePinnedTabs(from: captured))))
        XCTAssertFalse(request.ids.contains(ids[3]))
        XCTAssertTrue(selection.contains(.folder(folder)))
        try browser.send(browser.filingInNewFolder(request, in: .saved), for: request)
        session = browser.sessionSeed
        let result = session.spaces[0]
        let wrapper = try XCTUnwrap(result.folders.first { $0.id == folder }?.parentID)
        XCTAssertEqual(result.tabs.first { $0.id == ids[0] }?.folderID, wrapper)
        XCTAssertEqual(result.tabs.first { $0.id == ids[1] }?.folderID, wrapper)
        XCTAssertEqual(
            result.tabs.first { $0.id == ids[0] }?.splitGroupID, result.tabs.first { $0.id == ids[1] }?.splitGroupID)
        XCTAssertEqual(result.pinnedTabs.map(\.id), [ids[3]])
    }

    func testFortyTabRangeIncludesUnrealizedFolderRowsWithSixteenOrNoTargets() throws {
        var session = makeSession(count: 40)
        let folder = FolderState.Seed(title: "Long folder", location: .current)
        session.spaces[0].folders = [folder]
        for index in session.spaces[0].tabs.indices { session.spaces[0].tabs[index].folderID = folder.id }
        let browser = BrowserStore(seed: session)
        let opened = browser.sessionSeed
        let interaction = BrowserSidebarInteractionState.connected(to: browser)
        let space = try XCTUnwrap(browser.shownSpace)
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let ids = space.tabs.models.map(\.id)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 640),
            styleMask: [.borderless], backing: .buffered, defer: false)
        let targets = ids.prefix(16).enumerated().map { index, id in
            let target = BrowserNativeTabSelectionTarget.TargetView(
                frame: NSRect(x: 0, y: index * 40, width: 280, height: 40))
            target.browser = browser
            target.assignment = assignment
            target.tabID = id
            window.contentView?.addSubview(target)
            return target
        }
        for mounted in [true, false] {
            if !mounted {
                for target in targets { target.removeFromSuperview() }
            }
            let units = BrowserSidebarSelection.itemUnits(in: browser)
            browser.tabMultiSelection.click(ids[0], units: units)
            browser.tabMultiSelection.click(ids[39], units: units, shift: true)
            XCTAssertEqual(browser.tabMultiSelection.selectedIDs, Set(ids))
            XCTAssertEqual(BrowserSidebarSelection.capture(for: .tab(ids[0]), in: browser)?.ids, ids)
        }
        browser.tabMultiSelection.selectAll(units: BrowserSidebarSelection.itemUnits(in: browser))
        XCTAssertEqual(browser.tabMultiSelection.selectedIDs, Set(ids))
        XCTAssertEqual(BrowserSidebarSelection.capture(for: .folder(folder.id), in: browser)?.ids, ids)
    }

    func testLogicalOrderIncludesPinsMixedFoldersKeptSplitAndVisibleSections() throws {
        var session = makeSession(count: 8)
        let ids = session.spaces[0].tabs.map(\.id)
        let parent = FolderState.Seed(title: "Parent")
        let child = FolderState.Seed(title: "Child", parentID: parent.id, isCollapsed: true)
        let empty = FolderState.Seed(title: "Empty", orderAnchorTabID: ids[1])
        session.spaces[0].folders = [parent, child, empty]
        session.spaces[0].tabs[0].placement = .pinned
        for index in 1...4 { session.spaces[0].tabs[index].placement = .saved }
        for index in 2...3 { session.spaces[0].tabs[index].folderID = child.id }
        let group = UUID()
        for index in 2...3 { session.spaces[0].tabs[index].splitGroupID = group }
        session.spaces[0].tabs[4].folderID = parent.id
        session.spaces[0].tabs[7] = .startPage()
        session.spaces[0].settings.isSavedTabsExpanded = true
        let browser = makeBatchStore(session, showing: [session.spaces[0].id: ids[2]])
        let interaction = BrowserSidebarInteractionState.connected(to: browser)
        let space = try XCTUnwrap(browser.spaceModel(browser.selectedSpaceID))
        let assignment = BrowserSpaceRuntimeAssignment(spaceID: space.id, profileID: space.profileID)
        interaction.reconcileCollapsedFolders(
            in: space, selectedTabID: browser.selectedTabID(in: space.id), residentTabIDs: [ids[2], ids[3]])
        XCTAssertEqual(
            BrowserSidebarSelection.itemUnits(in: browser),
            [
                [.tab(ids[0])], [.folder(empty.id)], [.tab(ids[1])], [.folder(parent.id)], [.folder(child.id)],
                [.tab(ids[2]), .tab(ids[3])], [.tab(ids[4])], [.tab(ids[5])], [.tab(ids[6])],
            ])
        // A collapsed folder keeps the shown tab on screen inside every folder that holds it.
        XCTAssertTrue(browser.setFolderCollapsed(parent.id, in: space.id, isCollapsed: true))
        interaction.reconcileCollapsedFolders(
            in: space, selectedTabID: browser.selectedTabID(in: space.id), residentTabIDs: [ids[2], ids[3]])
        XCTAssertEqual(
            BrowserSidebarSelection.itemUnits(in: browser),
            [
                [.tab(ids[0])], [.folder(empty.id)], [.tab(ids[1])], [.folder(parent.id)], [.folder(child.id)],
                [.tab(ids[2]), .tab(ids[3])], [.tab(ids[5])], [.tab(ids[6])],
            ])
        browser.setSavedTabsExpanded(false, matching: assignment)
        XCTAssertEqual(BrowserSidebarSelection.units(in: browser), [[ids[0]], [ids[5]], [ids[6]]])
        // A capture holds only the picks the sidebar still shows.
        browser.tabMultiSelection.selectAll(units: [[.tab(ids[0])], [.tab(ids[1])], [.tab(ids[5])]])
        XCTAssertEqual(BrowserSidebarSelection.capture(for: .tab(ids[0]), in: browser)?.ids, [ids[0], ids[5]])
    }

    func testCollapsedVisibilitySurvivesUnmountingButIsScopedToWindowAssignmentAndResidency() throws {
        var session = makeSession(count: 3)
        let folder = FolderState.Seed(title: "Kept", location: .current, isCollapsed: true)
        session.spaces[0].folders = [folder]
        let ids = session.spaces[0].tabs.map(\.id)
        for index in 0...1 { session.spaces[0].tabs[index].folderID = folder.id }
        let firstBrowser = BrowserStore(seed: session)
        let secondBrowser = BrowserStore(seed: session)
        let first = BrowserSidebarInteractionState.connected(to: firstBrowser)
        let second = BrowserSidebarInteractionState.connected(to: secondBrowser)
        let space = try XCTUnwrap(firstBrowser.spaceModel(session.spaces[0].id))
        let secondSpace = try XCTUnwrap(secondBrowser.spaceModel(session.spaces[0].id))
        let assignment = BrowserFolderRuntimeAssignment(
            folderID: folder.id, spaceID: space.id,
            profileID: space.profileID)
        first.reconcileCollapsedFolders(in: space, selectedTabID: ids[0], residentTabIDs: [ids[0], ids[1]])
        second.reconcileCollapsedFolders(in: secondSpace, selectedTabID: ids[1], residentTabIDs: [ids[0], ids[1]])
        first.reconcileCollapsedFolders(in: space, selectedTabID: ids[2], residentTabIDs: [ids[0], ids[1]])
        second.reconcileCollapsedFolders(in: secondSpace, selectedTabID: ids[2], residentTabIDs: [ids[0], ids[1]])
        XCTAssertEqual(first.collapsedFolderVisibility(for: assignment).state.keptTabID, ids[0])
        XCTAssertEqual(second.collapsedFolderVisibility(for: assignment).state.keptTabID, ids[1])
        first.reconcileCollapsedFolders(in: space, selectedTabID: ids[2], residentTabIDs: [ids[1]])
        XCTAssertNil(first.collapsedFolderVisibility(for: assignment).state.keptTabID)
        XCTAssertEqual(second.collapsedFolderVisibility(for: assignment).state.keptTabID, ids[1])
        XCTAssertTrue(secondBrowser.setFolderCollapsed(folder.id, in: space.id, isCollapsed: false))
        second.reconcileCollapsedFolders(in: secondSpace, selectedTabID: ids[2], residentTabIDs: [ids[0], ids[1]])
        XCTAssertNil(second.collapsedFolderVisibility(for: assignment).state.keptTabID)
        first.reconcileCollapsedFolders(in: space, selectedTabID: ids[0], residentTabIDs: [ids[0]])
        let oldBox = first.collapsedFolderVisibility(for: assignment)
        first.pruneCollapsedFolders(keepingFoldersOf: [])
        XCTAssertNil(oldBox.state.keptTabID)
        XCTAssertFalse(first.collapsedFolderVisibility(for: assignment) === oldBox)
        first.reconcileCollapsedFolders(in: space, selectedTabID: ids[0], residentTabIDs: [ids[0]])
        let previousProfileBox = first.collapsedFolderVisibility(for: assignment)
        // The same Space under another profile, as another window's core holds it.
        var reprofiled = session
        let copy = session.spaces[0]
        reprofiled.spaces[0] = SpaceState.Seed(
            id: copy.id, name: copy.settings.name, symbol: copy.settings.symbol, accent: copy.settings.accent,
            folders: copy.folders, tabs: copy.tabs)
        let reprofiledBrowser = BrowserStore(seed: reprofiled)
        let newSpace = try XCTUnwrap(reprofiledBrowser.spaceModel(copy.id))
        first.pruneCollapsedFolders(keepingFoldersOf: [newSpace])
        XCTAssertNil(previousProfileBox.state.keptTabID)
        let newAssignment = BrowserFolderRuntimeAssignment(
            folderID: folder.id, spaceID: newSpace.id,
            profileID: newSpace.profileID)
        first.reconcileCollapsedFolders(in: newSpace, selectedTabID: ids[0], residentTabIDs: [ids[0]])
        XCTAssertEqual(first.collapsedFolderVisibility(for: newAssignment).state.keptTabID, ids[0])
        first.browserWillResetSession()
        XCTAssertNil(first.collapsedFolderVisibility(for: newAssignment).state.keptTabID)
    }

    func testLogicalSelectionDoesNotExposeALockedSpaceWithoutLiveAuthorization() throws {
        var session = makeSession(count: 2)
        session.spaces[0].settings.accessPolicy = .deviceOwnerAuthentication
        let browser = BrowserStore(seed: session)
        let opened = browser.sessionSeed
        let interaction = BrowserSidebarInteractionState.connected(to: browser)
        XCTAssertEqual(BrowserSidebarSelection.itemUnits(in: browser), [])
        let access = BrowserSpaceAccessController()
        interaction.sidebarSpaceAccess = access
        XCTAssertEqual(BrowserSidebarSelection.itemUnits(in: browser), [])
    }

    /// A store showing the first Space with `showing` as each Space's tab (the
    /// first tab when empty). `fallbackTabID` is the tab shown just before, so
    /// dismissing the shown tab returns to it.
    private func makeBatchStore(
        _ session: SessionState.Seed, showing tabs: [UUID: UUID] = [:], fallbackTabID: UUID? = nil
    ) -> BrowserStore {
        let preferences = BrowserLinkPreferenceStore()
        preferences.setBehavior(.followsMovedTabs, isOn: false)
        let spaceID = session.spaces[0].id
        let shown = tabs.isEmpty ? session.spaces[0].tabs.first.map { [spaceID: $0.id] } ?? [:] : tabs
        var opening = shown
        if let fallbackTabID { opening[spaceID] = fallbackTabID }
        let browser = BrowserStore(seed: session, showing: spaceID, tabs: opening, linkPreferences: preferences)
        if fallbackTabID != nil, let shownTab = shown[spaceID] { browser.activateSessionTab(shownTab, in: spaceID) }
        return browser
    }

    /// Organizes a fixture through the store's commands in its first Space.
    private func organized(
        _ session: SessionState.Seed, _ build: (BrowserStore, SpaceModel) throws -> Void
    ) throws -> SessionState.Seed {
        let browser = makeBatchStore(session)
        try build(browser, try XCTUnwrap(browser.shownSpace))
        return browser.sessionSeed
    }

    private func makeSession(count: Int) -> SessionState.Seed {
        var space = SpaceState.Seed.blank(number: 1)
        space.tabs = (0..<count).map { index in
            TabState.Seed(
                title: "Tab \(index)", url: URL(string: "https://example.com/\(index)"), symbol: "globe",
                placement: .current)
        }
        // A session as the core opens it names its launch Space.
        return SessionState.Seed(spaces: [space], defaultSpaceID: space.id)
    }
}
