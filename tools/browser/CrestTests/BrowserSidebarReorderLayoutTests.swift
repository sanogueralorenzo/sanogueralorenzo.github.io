import Foundation
import XCTest

@testable import Crest

final class BrowserSidebarReorderLayoutTests: XCTestCase {
    private let space = BrowserSpaceRuntimeAssignment(spaceID: UUID(), profileID: UUID())
    private let source = BrowserSidebarReorderItemID.folder(UUID())
    private let current = BrowserSidebarReorderSection.tabs(placement: .current, folderID: nil)

    @MainActor
    func testNativeDragCompletionClearsTheMatchingLiftButNotANewerSession() throws {
        let state = BrowserSidebarReorderState()
        let item = BrowserSidebarReorderItem.tab(
            .init(tabID: UUID(), spaceID: space.spaceID, profileID: space.profileID))
        state.stage(item: item, section: current)
        let first = try XCTUnwrap(state.sessionToken)
        state.update(pointer: CGPoint(x: 50, y: 100))
        XCTAssertEqual(state.sessionToken, first)
        XCTAssertTrue(state.hidesSource(item.id))
        state.cancel(session: first)
        XCTAssertFalse(state.hasLiftInFlight)
        XCTAssertFalse(state.hidesSource(item.id))
        XCTAssertNil(state.layout.gapFrame)

        state.stage(item: item, section: current)
        let second = try XCTUnwrap(state.sessionToken)
        XCTAssertNotEqual(first, second)
        state.update(pointer: CGPoint(x: 50, y: 100))
        state.cancel(session: first)
        XCTAssertTrue(state.isDragging)
        XCTAssertEqual(state.sessionToken, second)
        state.cancel(session: second)
        XCTAssertFalse(state.hasLiftInFlight)
    }

    @MainActor
    func testExplicitSpaceDropOverridesALargeGapAndTheMovingEdgeProbe() throws {
        let destination = BrowserSpaceRuntimeAssignment(spaceID: UUID(), profileID: space.profileID)
        let spaceZone = BrowserSidebarReorderZone(
            target: .space(destination), frame: CGRect(x: 104, y: 988, width: 40, height: 30))
        let sectionZone = BrowserSidebarReorderZone(
            target: .section(current), frame: CGRect(x: 8, y: 100, width: 240, height: 1800))
        let previous = BrowserSidebarReorderTarget(kind: .insert(section: current, beforeID: .tab(UUID()), index: 1))
        let tab = BrowserSidebarReorderItem.tab(
            .init(tabID: UUID(), spaceID: space.spaceID, profileID: space.profileID))
        var tallGap = BrowserSidebarReorderLayout(
            sourceID: tab.id, sourceFrame: CGRect(x: 8, y: 100, width: 240, height: 44), hiddenIDs: [tab.id],
            gap: .init(
                section: current, anchor: .emptySection(current),
                frame: CGRect(x: 8, y: 220, width: 240, height: 44), containingFolders: []))
        tallGap.batchHeight = 40 * 44
        let pointer = CGPoint(x: spaceZone.frame.midX, y: spaceZone.frame.midY)
        XCTAssertTrue(try XCTUnwrap(tallGap.gapFrame).contains(pointer))
        let lift = BrowserSidebarReorderState.Lift(
            item: tab, section: current, rowSize: CGSize(width: 240, height: 44), grabOffset: .zero)
        func resolve(
            _ lift: BrowserSidebarReorderState.Lift, layout: BrowserSidebarReorderLayout,
            pointer: CGPoint, insertionPoint: CGPoint
        ) -> BrowserSidebarReorderTarget? {
            BrowserSidebarReorderAim(
                lift: lift, pointer: pointer, insertionPoint: insertionPoint, layout: layout, pinned: nil,
                zones: [sectionZone, spaceZone], rows: [:], splitCards: [:]
            ).target(previousTarget: previous)
        }
        XCTAssertEqual(
            resolve(lift, layout: tallGap, pointer: pointer, insertionPoint: pointer)?.kind,
            .space(destination), "A batch gap must not mask fixed Space picker targets.")
        let insideList = CGPoint(x: pointer.x, y: 500)
        XCTAssertEqual(
            resolve(lift, layout: tallGap, pointer: insideList, insertionPoint: insideList), previous,
            "Ordinary list movement still preserves the existing gap.")
        let folderLift = BrowserSidebarReorderState.Lift(
            item: .folder(.init(folderID: UUID(), spaceID: space.spaceID, profileID: space.profileID)),
            section: current, rowSize: CGSize(width: 240, height: 1600), grabOffset: .zero)
        XCTAssertEqual(
            resolve(
                folderLift, layout: BrowserSidebarReorderLayout(), pointer: pointer,
                insertionPoint: CGPoint(x: pointer.x, y: pointer.y + 1600))?.kind,
            .space(destination), "An explicit pointer target takes precedence over the moving row edge.")
    }

    func testAdjacentFolderEdgesOfferTheirParentSectionForTabs() {
        for placement in [TabPlacement.saved, .current] {
            let parent = BrowserSidebarReorderSection.tabs(placement: placement, folderID: nil)
            let first = UUID()
            let second = UUID()
            let zones = [
                BrowserSidebarReorderZone(
                    target: .section(parent), frame: CGRect(x: 8, y: 100, width: 240, height: 240)),
                BrowserSidebarReorderZone(
                    target: .section(.tabs(placement: placement, folderID: first)),
                    frame: CGRect(x: 8, y: 100, width: 240, height: 80)),
                BrowserSidebarReorderZone(
                    target: .section(.tabs(placement: placement, folderID: second)),
                    frame: CGRect(x: 8, y: 180, width: 240, height: 80)),
            ]
            let item = BrowserSidebarReorderItem.tab(
                .init(tabID: UUID(), spaceID: space.spaceID, profileID: space.profileID))
            for y in [CGFloat(176), 180, 184] {
                XCTAssertEqual(
                    BrowserSidebarReorderZone.aimed(at: CGPoint(x: 100, y: y), in: zones, accepting: item)?.target,
                    .section(parent))
            }
            XCTAssertEqual(
                BrowserSidebarReorderZone.aimed(at: CGPoint(x: 100, y: 210), in: zones, accepting: item)?.target,
                .section(.tabs(placement: placement, folderID: second)))
        }
    }

    @MainActor
    func testSavedFolderOutlineRetainsAnUnfiledTabBetweenFolders() {
        let first = FolderState.Seed(title: "First")
        let second = FolderState.Seed(title: "Second")
        let firstTab = TabState.Seed(
            title: "First member", url: URL(string: "https://example.com/"), placement: .saved, folderID: first.id)
        let middle = TabState.Seed(title: "Between", url: URL(string: "https://example.com/"), placement: .saved)
        let secondTab = TabState.Seed(
            title: "Second member", url: URL(string: "https://example.com/"), placement: .saved, folderID: second.id)
        var space = SpaceState.Seed.blank(number: 1)
        space.folders = [first, second]
        space.tabs += [firstTab, middle, secondTab]
        let session = SessionState.Seed(spaces: [space], defaultSpaceID: space.id)
        XCTAssertEqual(
            session.sidebarRowIDs(in: space.id, location: .saved),
            [.folder(first.id), .tab(middle.id), .folder(second.id)])
    }

    @MainActor
    func testExpandedFolderPassesItsSiblingWithoutDraggingAnEntireFolderHeight() throws {
        let state = BrowserSidebarReorderState()
        let siblingID = UUID()
        let sibling = row(.folder(siblingID), y: 260, height: 80)
        let following = row(.tab(UUID()), y: 340, height: 40)
        for row in [row(source, y: 100, height: 160), sibling, following] {
            state.register(row: row, owner: UUID())
        }
        state.register(
            zone: .init(target: .section(current), frame: CGRect(x: 8, y: 100, width: 240, height: 280)), for: UUID())
        state.register(
            zone: .init(
                target: .section(.folders(parentID: siblingID)),
                frame: CGRect(x: 8, y: 300, width: 240, height: 40)), for: UUID())
        state.begin(
            item: .folder(
                .init(folderID: try XCTUnwrap(source.folderID), spaceID: space.spaceID, profileID: space.profileID)),
            section: current, at: CGPoint(x: 80, y: 120))
        state.update(pointer: CGPoint(x: 80, y: 168))
        XCTAssertEqual(state.resolvedTarget?.kind, .insert(section: current, beforeID: following.id, index: 1))

        // Animation measurements and a held pointer cannot oscillate the slot.
        for _ in 0..<50 {
            state.register(row: row(.folder(siblingID), y: 100, height: 80), owner: UUID())
            state.update(pointer: CGPoint(x: 80, y: 168))
        }
        XCTAssertEqual(state.resolvedTarget?.kind, .insert(section: current, beforeID: following.id, index: 1))

        state.update(pointer: CGPoint(x: 80, y: 130))
        XCTAssertEqual(state.resolvedTarget?.kind, .insert(section: current, beforeID: sibling.id, index: 0))

        state.cancel()
        XCTAssertFalse(state.layout.isActive)
        XCTAssertNil(state.layout.gapFrame)
    }

    private func row(_ id: BrowserSidebarReorderItemID, y: CGFloat, height: CGFloat) -> BrowserSidebarReorderRow {
        BrowserSidebarReorderRow(
            id: id, space: space, section: current,
            frame: CGRect(x: 8, y: y, width: 240, height: height))
    }

}
