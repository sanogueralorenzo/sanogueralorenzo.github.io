import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import XCTest

@testable import Crest

/// Native sidebar input must resolve a page target and commit the same split.
/// Each case owns an in-memory session, ephemeral pages, and its window.
@MainActor
final class BrowserSplitDragToSplitWindowTests: XCTestCase {

    func testAPointerDragFromTheSidebarIntoThePageOpensAndCommitsASplit() throws {
        let fixture = try makeHostedWindow()
        defer { fixture.input.close() }
        let state = fixture.model.sidebarInteraction.sidebarReorderState

        let contentCard = try XCTUnwrap(state.orderedSplitCardFrames.first)
        XCTAssertEqual(
            state.orderedSplitCardFrames.count,
            1,
            "The lone tab on show has to register as the card a drop joins."
        )

        let rowFrame = try XCTUnwrap(
            state.frame(ofRow: .tab(fixture.joiner.id)),
            "The sidebar row for the tab about to be dragged never measured."
        )
        let start = CGPoint(x: rowFrame.midX, y: rowFrame.midY)
        // Well inside the content area, past the card's midpoint, so the drop
        // resolves to the slot after the tab already on show.
        let overPage = CGPoint(x: contentCard.maxX - 60, y: contentCard.midY)

        fixture.send(.leftMouseDown, at: start)
        for step in 1...12 {
            let fraction = CGFloat(step) / 12
            fixture.send(
                .leftMouseDragged,
                at: CGPoint(
                    x: start.x + (overPage.x - start.x) * fraction,
                    y: start.y + (overPage.y - start.y) * fraction
                )
            )
        }

        XCTAssertEqual(
            state.resolvedTarget?.kind,
            .splitInsert(assignment: fixture.assignment, index: 1),
            "A pointer past the presented card resolves the slot after it."
        )
        XCTAssertTrue(
            state.hasEnteredSplitContent,
            "Reaching the content area latches the columns layout for the drag."
        )
        XCTAssertEqual(
            state.liftTargetShape,
            .webpageCard,
            "The lift morphs toward what the drop would make of it."
        )
        XCTAssertEqual(
            state.liftPreview?.tabID,
            fixture.joiner.id,
            "The lift is drawn by the window host, not by the row."
        )

        let shrunkCard = try XCTUnwrap(state.orderedSplitCardFrames.first)
        XCTAssertLessThan(
            shrunkCard.width,
            contentCard.width,
            "The drop column has to open a real slot beside the presented card."
        )

        fixture.send(.leftMouseUp, at: overPage)
        let space = try XCTUnwrap(
            fixture.model.browser.spaceModel(fixture.assignment.spaceID)
        )
        let groupID = try XCTUnwrap(
            space.shownSplit(containing: fixture.joiner.id),
            "Releasing over the page has to commit the split."
        )
        XCTAssertEqual(
            space.splitMembers(of: groupID).map(\.title),
            ["Presented", "Joiner"]
        )
        XCTAssertEqual(fixture.model.browser.selectedTabID(in: space.id), fixture.joiner.id)
        XCTAssertFalse(state.isDragging)
        XCTAssertNil(state.liftPreview)
        pump(0.4)

    }

    func testSplitMemberDragDetachesOnlyThatTabWhileTheHeaderOwnsTheGroupDrag() throws {
        let fixture = try makeHostedWindow(groupsJoiner: true)
        defer { fixture.input.close() }
        let state = fixture.model.sidebarInteraction.sidebarReorderState
        let original = fixture.model.browser.sessionSeed
        let originalSelection = fixture.model.browser.selectedTabID(in: fixture.assignment.spaceID)
        let space = try XCTUnwrap(fixture.model.browser.spaceModel(fixture.assignment.spaceID))
        let group = try XCTUnwrap(space.shownSplit(containing: fixture.joiner.id))
        let members = space.splitMembers(of: group).map(\.value)
        let groupFrame = try XCTUnwrap(state.frame(ofRow: .splitGroup(group)))
        let memberFrame = try XCTUnwrap(state.frame(ofRow: .tab(fixture.joiner.id)))
        let destination = try XCTUnwrap(state.frame(ofRow: .tab(fixture.presented.id)))
        let drop = CGPoint(x: destination.midX, y: destination.minY)
        let header = CGPoint(x: groupFrame.midX, y: (groupFrame.minY + memberFrame.minY) / 2)

        fixture.beginDrag(from: header, to: drop)
        guard case .splitGroup(let liftedGroup) = state.lift?.item else {
            return XCTFail("The split header must lift the whole group.")
        }
        XCTAssertEqual(liftedGroup.memberTabIDs, members.map(\.id))
        state.cancel()
        fixture.send(.leftMouseUp, at: drop)
        XCTAssertEqual(fixture.model.browser.sessionSeed, original, "Cancelling must preserve membership and ordering.")
        pump(0.4)

        fixture.model.browser.tabMultiSelection.clear()
        fixture.model.browser.tabMultiSelection.click(
            fixture.joiner.id,
            units: BrowserSidebarSelection.units(in: fixture.model.browser), command: true)
        XCTAssertTrue(members.allSatisfy { fixture.model.browser.tabMultiSelection.contains($0.id) })
        let selectedMemberFrame = try XCTUnwrap(state.frame(ofRow: .tab(fixture.joiner.id)))
        fixture.beginDrag(from: CGPoint(x: selectedMemberFrame.midX, y: selectedMemberFrame.midY), to: drop)
        XCTAssertEqual(state.lift?.item.selection?.ids, members.map(\.id))
        XCTAssertEqual(state.lift?.item.id, .splitGroup(group))
        state.cancel()
        fixture.send(.leftMouseUp, at: drop)
        fixture.model.browser.tabMultiSelection.clear()
        pump(0.4)

        let currentMemberFrame = try XCTUnwrap(state.frame(ofRow: .tab(fixture.joiner.id)))
        fixture.beginDrag(from: CGPoint(x: currentMemberFrame.midX, y: currentMemberFrame.midY), to: drop)
        guard case .tab(let liftedTab) = state.lift?.item else {
            return XCTFail("A member row must lift its own tab.")
        }
        XCTAssertEqual(liftedTab.tabID, fixture.joiner.id)
        XCTAssertNil(liftedTab.selection)
        XCTAssertEqual(
            state.resolvedTarget?.kind,
            .insert(section: .tabs(placement: .current, folderID: nil), beforeID: .tab(fixture.presented.id), index: 0))
        fixture.send(.leftMouseUp, at: drop)

        let updated = try XCTUnwrap(fixture.model.browser.spaceModel(fixture.assignment.spaceID))
        XCTAssertNil(updated.tabs.models.first(where: { $0.id == fixture.joiner.id })?.splitGroupID)
        XCTAssertEqual(updated.tabs.models.first?.id, fixture.joiner.id)
        XCTAssertEqual(updated.splitMembers(of: group).map(\.id), members.dropFirst().map(\.id))
        XCTAssertEqual(fixture.model.browser.selectedTabID(in: updated.id), originalSelection)
    }

    // MARK: - Fixture

    /// A window showing one tab, with a second tab in the sidebar to drag.
    @MainActor
    private struct HostedWindow {
        let input: BrowserNativeMouseInput
        let model: BrowserRootModel
        let assignment: BrowserSpaceRuntimeAssignment
        let presented: TabState.Seed
        let joiner: TabState.Seed

        func send(_ type: NSEvent.EventType, at global: CGPoint) {
            input.send(type, at: global)
        }

        func beginDrag(from start: CGPoint, to end: CGPoint) {
            send(.leftMouseDown, at: start)
            for step in 1...12 {
                let fraction = CGFloat(step) / 12
                send(
                    .leftMouseDragged,
                    at: CGPoint(
                        x: start.x + (end.x - start.x) * fraction,
                        y: start.y + (end.y - start.y) * fraction))
            }
        }
    }

    private func makeHostedWindow(
        groupsJoiner: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> HostedWindow {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let presented = TabState.Seed(
            id: Self.uuid(0x01),
            title: "Presented",
            url: URL(string: "about:blank"),
            symbol: "globe",
            placement: .current,
            lastActivatedAt: date
        )
        var joiner = TabState.Seed(
            id: Self.uuid(0x02),
            title: "Joiner",
            url: URL(string: "about:blank"),
            symbol: "globe",
            placement: .current,
            lastActivatedAt: date
        )
        var tabs = [presented, joiner]
        if groupsJoiner {
            let group = UUID()
            joiner.splitGroupID = group
            tabs = [presented, joiner]
            for index in 0..<2 {
                var member = TabState.Seed(
                    title: "Group member \(index)", url: URL(string: "about:blank"), symbol: "globe",
                    placement: .current, lastActivatedAt: date)
                member.splitGroupID = group
                tabs.append(member)
            }
        }
        let space = SpaceState.Seed(
            id: Self.uuid(0x03),
            profileID: Self.uuid(0x04),
            name: "Drag To Split",
            symbol: "books.vertical.fill",
            accent: .indigo,
            branding: SpaceAccent.indigo.house,
            folders: [],
            tabs: tabs
        )
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [space]),
            showing: space.id, tabs: [space.id: presented.id]
        )
        let model = BrowserRootModel(
            browser: browser,
            pages: BrowserPagePool(
                browser: browser,
                browsingMode: .privateBrowsing,
                usesEphemeralWebsiteDataStores: true
            ),
            chrome: BrowserChromeState(sidebarIsPresented: true),
            spaceAccess: BrowserSpaceAccessController(),
            windowState: nil,
            startupBehavior: .showStartPage,
            persistedSidebarWidth: BrowserChromeLayout.sidebarIdealWidth
        )

        let host = NSHostingView(
            rootView: BrowserSplitDragToSplitTestSurface(model: model)
                .environment(model.sidebarInteraction)
        )
        let window = NSWindow(
            contentRect: CGRect(x: 120, y: 120, width: 1_160, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        // ARC owns this window; letting AppKit release it on close would
        // over-release it the moment the test's autorelease pool drains.
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        pump(0.6)

        return HostedWindow(
            input: BrowserNativeMouseInput(window: window),
            model: model,
            assignment: BrowserSpaceRuntimeAssignment(space: space),
            presented: presented,
            joiner: joiner
        )
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x44, 0x52, 0x41, 0x47, 0x54, 0x4F, 0x53, 0x50,
                0x4C, 0x49, 0x54, 0x57, 0x49, 0x4E, 0x44, finalByte
            )
        )
    }
}

/// Runs the main run loop long enough for SwiftUI to answer what just happened.
@MainActor
private func pump(_ seconds: TimeInterval) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

/// The shell as the app composes it, with nothing standing in for it.
private struct BrowserSplitDragToSplitTestSurface: View {
    let model: BrowserRootModel

    @Namespace private var commandSurfaceNamespace
    @Namespace private var tabPromotionNamespace
    @State private var sidebarWidth = Double(
        BrowserChromeLayout.sidebarIdealWidth
    )

    var body: some View {
        BrowserRootShell(
            model: model,
            transientBrowsing: BrowserTransientBrowsingCoordinator(),
            spaceSettingsPresentation: BrowserSpaceSettingsPresentationState(),
            shortcuts: nil,
            storedSidebarWidth: $sidebarWidth,
            commandSurfaceNamespace: commandSurfaceNamespace,
            tabPromotionNamespace: tabPromotionNamespace
        )
    }
}
