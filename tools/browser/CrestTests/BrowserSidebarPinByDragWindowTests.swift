import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import XCTest

@testable import Crest

/// The floating sidebar must receive pin drops instead of the page behind it.
@MainActor
final class BrowserSidebarPinByDragWindowTests: XCTestCase {

    /// The same gesture with the sidebar floating over the page, aimed at the
    /// seam above the grid rather than at a tile.
    ///
    /// A floating sidebar is drawn on top of the window's content area, so that
    /// area's drop zone lies underneath the whole card — every seam the
    /// sidebar's own layout leaves, the address band above the grid included.
    /// While the page owned those seams the grid answered only inside its exact
    /// rectangle: no slot opened, the lift morphed toward a page card instead of
    /// a tile, and a Space whose content area declined the drop resolved nothing
    /// at all. Aiming short of a run is how every other run in the sidebar is
    /// reached, so it has to reach this one too.
    func testPinningWorksWithTheSidebarFloatingOverThePage() throws {
        let fixture = try makeHostedWindow()
        defer { fixture.input.close() }
        let state = fixture.model.sidebarInteraction.sidebarReorderState
        fixture.model.chrome.columnVisibility = .detailOnly
        fixture.model.isFloatingSidebarPresented = true
        pump(0.8)

        let tileFrame = try XCTUnwrap(
            state.frame(ofRow: .tab(fixture.pinned.id))
        )
        let rowFrame = try XCTUnwrap(
            state.frame(ofRow: .tab(fixture.joiner.id))
        )
        // Above the grid, in the band the address field occupies: short of the
        // run, the way appending to a list means aiming below its last row.
        let aboveGrid = CGPoint(x: tileFrame.midX, y: tileFrame.minY - 24)
        fixture.drag(from: rowFrame, to: aboveGrid)

        XCTAssertEqual(
            state.resolvedTarget?.section,
            .tabs(placement: .pinned, folderID: nil),
            "A pointer aimed at the grid must not resolve the page behind it."
        )
        XCTAssertEqual(state.liftTargetShape, .pinnedTile)

        fixture.send(.leftMouseUp, at: aboveGrid)
        pump(0.4)

        let space = try XCTUnwrap(
            fixture.model.browser.spaceModel(fixture.assignment.spaceID)
        )
        XCTAssertTrue(
            space.pinnedTabs.contains { $0.title == "Joiner" },
            "Releasing there has to pin the tab, not hand it to the page."
        )
    }

    // MARK: - Fixture

    /// A window showing one presented tab, one pinned tab, and a second current
    /// tab in the sidebar to drag onto the grid.
    @MainActor
    private struct HostedWindow {
        let input: BrowserNativeMouseInput
        let model: BrowserRootModel
        let assignment: BrowserSpaceRuntimeAssignment
        let pinned: TabState.Seed
        let presented: TabState.Seed
        let joiner: TabState.Seed

        /// Presses inside `origin` and pulls to `destination`, leaving the
        /// button down so the resolved target can be read mid-drag.
        func drag(from origin: CGRect, to destination: CGPoint) {
            let start = CGPoint(x: origin.midX, y: origin.midY)
            send(.leftMouseDown, at: start)
            for step in 1...12 {
                let fraction = CGFloat(step) / 12
                send(
                    .leftMouseDragged,
                    at: CGPoint(
                        x: start.x + (destination.x - start.x) * fraction,
                        y: start.y + (destination.y - start.y) * fraction
                    )
                )
            }
        }

        func send(_ type: NSEvent.EventType, at global: CGPoint) {
            input.send(type, at: global)
        }
    }

    private func makeHostedWindow() throws -> HostedWindow {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        func makeTab(
            _ byte: UInt8,
            _ title: String,
            _ placement: Crest.TabPlacement
        ) -> TabState.Seed {
            TabState.Seed(
                id: Self.uuid(byte),
                title: title,
                url: URL(string: "about:blank"),
                symbol: "globe",
                placement: placement,
                lastActivatedAt: date
            )
        }
        let pinned = makeTab(0x01, "Pinned", .pinned)
        let saved = makeTab(0x02, "Saved", .saved)
        let presented = makeTab(0x03, "Presented", .current)
        let joiner = makeTab(0x04, "Joiner", .current)
        let space = SpaceState.Seed(
            id: Self.uuid(0x05),
            profileID: Self.uuid(0x06),
            name: "Pin By Drag",
            symbol: "books.vertical.fill",
            accent: .indigo,
            branding: SpaceAccent.indigo.house,
            folders: [],
            tabs: [pinned, saved, presented, joiner]
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
            rootView: BrowserSidebarPinByDragTestSurface(model: model)
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
            pinned: pinned,
            presented: presented,
            joiner: joiner
        )
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x50, 0x49, 0x4E, 0x42, 0x59, 0x44, 0x52, 0x41,
                0x47, 0x57, 0x49, 0x4E, 0x44, 0x4F, 0x57, finalByte
            )
        )
    }
}

/// The shell as the app composes it, with nothing standing in for it.
private struct BrowserSidebarPinByDragTestSurface: View {
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

/// Runs the main run loop long enough for SwiftUI to answer what just happened.
@MainActor
private func pump(_ seconds: TimeInterval) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}
