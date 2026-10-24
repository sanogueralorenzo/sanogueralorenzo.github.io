import AppKit
import SwiftUI
import XCTest

@testable import Crest

@MainActor
final class BrowserTabTearOffWindowTests: XCTestCase {
    func testNativeDragOutsideOnlyWindowWaitsForBlankWindowThenMovesTab() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.source.pages.select()
        let page = try XCTUnwrap(fixture.source.pages.activePage)
        let row = try XCTUnwrap(fixture.root.sidebarInteraction.sidebarReorderState.frame(ofRow: .tab(fixture.tabID)))
        let grabFraction = CGPoint(x: 0.25, y: 0.75)
        fixture.drag(from: row, grabFraction: grabFraction)
        // Drag decorations are separate native windows but cannot accept a drop.
        let sourceWindow = try XCTUnwrap(fixture.source.window)
        let point = sourceWindow.convertPoint(
            toScreen: CGPoint(
                x: fixture.outside.x, y: (sourceWindow.contentView?.bounds.height ?? 0) - fixture.outside.y))
        let preview = NSPanel(
            contentRect: CGRect(x: point.x - 40, y: point.y - 40, width: 80, height: 80),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        preview.isReleasedWhenClosed = false
        preview.ignoresMouseEvents = true
        preview.orderFront(nil)
        defer { preview.close() }
        fixture.input.send(.leftMouseUp, at: fixture.outside)
        fixture.pump()

        let request = try XCTUnwrap(fixture.request)
        XCTAssertEqual(request.kind, .temporary)
        XCTAssertEqual(fixture.source.browser.shownTab?.id, fixture.tabID)
        let destination = try XCTUnwrap(fixture.coordinator.existingModel(for: request.id))
        XCTAssertTrue(destination.browser.shownSpace?.tabs.models.isEmpty == true)
        let placement = try XCTUnwrap(destination.tearOffPlacement)
        XCTAssertEqual(placement.assignment.tabID, fixture.tabID)
        XCTAssertEqual(fixture.capturedDropPoint, point)
        XCTAssertEqual(placement.dropPoint, point)
        let capturedGrab = try XCTUnwrap(fixture.capturedGrabFraction)
        XCTAssertEqual(capturedGrab.x, grabFraction.x, accuracy: 0.001)
        XCTAssertEqual(capturedGrab.y, grabFraction.y, accuracy: 0.001)
        XCTAssertEqual(placement.grabFraction, capturedGrab)
        XCTAssertTrue(placement.isPending)

        fixture.hostDestination(destination)
        fixture.coordinator.preparePresentation(fixture.destinationWindow, for: request.id)
        XCTAssertEqual(fixture.destinationWindow.alphaValue, 0)
        let sourceRow = BrowserSidebarReorderRow(
            id: .tab(fixture.tabID),
            space: .init(spaceID: placement.assignment.spaceID, profileID: placement.assignment.profileID),
            section: .tabs(placement: .current, folderID: nil), frame: row)
        fixture.coordinator.didMeasureRow(sourceRow, in: request.id)
        XCTAssertTrue(placement.isPending, "A row still owned by the source cannot reveal an empty destination")
        XCTAssertEqual(fixture.destinationWindow.alphaValue, 0)
        fixture.destinationWindow.orderFront(nil)
        fixture.coordinator.attach(fixture.destinationWindow, to: request.id)
        fixture.pump()

        XCTAssertEqual(destination.browser.shownTab?.id, fixture.tabID)
        XCTAssertTrue(destination.pages.activePage === page)
        XCTAssertTrue(page.host === destination.pages)
        XCTAssertNil(fixture.source.pages.residentPage(matching: placement.assignment))
        XCTAssertTrue(fixture.source.browser.shownSpace?.tabs.models.isEmpty == true)
        XCTAssertNotNil(fixture.coordinator.existingModel(for: fixture.source.id))
        XCTAssertTrue(fixture.source.window?.isVisible == true)
        XCTAssertTrue(fixture.completedPlacementFromRow, "The destination's measured row must finish placement")
        XCTAssertFalse(placement.isPending)
        XCTAssertTrue(fixture.destinationWindow.isVisible)
        XCTAssertEqual(fixture.destinationWindow.alphaValue, 1)

        let measuredRow = try XCTUnwrap(fixture.measuredDestinationRow)
        let lateRow = BrowserSidebarReorderRow(
            id: measuredRow.id, space: measuredRow.space, section: measuredRow.section,
            frame: measuredRow.frame.offsetBy(dx: 33, dy: 22))
        let unrelatedRow = BrowserSidebarReorderRow(
            id: .tab(UUID()), space: measuredRow.space, section: measuredRow.section, frame: lateRow.frame)
        let destinationFrame = fixture.destinationWindow.frame
        let sourceFrame = sourceWindow.frame
        fixture.destinationWindow.orderOut(nil)
        sourceWindow.orderOut(nil)
        fixture.coordinator.didMeasureRow(lateRow, in: request.id)
        fixture.coordinator.didMeasureRow(unrelatedRow, in: request.id)
        fixture.coordinator.didMeasureRow(lateRow, in: fixture.source.id)
        fixture.pump()
        XCTAssertEqual(fixture.destinationWindow.frame, destinationFrame)
        XCTAssertEqual(sourceWindow.frame, sourceFrame)
        XCTAssertFalse(fixture.destinationWindow.isVisible, "Completed placement must not reveal the window again")
        XCTAssertFalse(sourceWindow.isVisible, "A destination row must not reveal another window")
    }

    func testEscapeCancelsSingleTabTearOffUntilMouseRelease() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let row = try XCTUnwrap(fixture.root.sidebarInteraction.sidebarReorderState.frame(ofRow: .tab(fixture.tabID)))
        fixture.drag(from: row)
        XCTAssertTrue(fixture.root.sidebarInteraction.sidebarReorderState.hasLiftInFlight)
        let escape = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: fixture.source.window!.windowNumber, context: nil,
                characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        NSApp.sendEvent(escape)
        fixture.input.send(.leftMouseDragged, at: CGPoint(x: fixture.outside.x + 5, y: fixture.outside.y))
        fixture.input.send(.leftMouseUp, at: fixture.outside)
        fixture.pump()

        XCTAssertNil(fixture.request)
        XCTAssertEqual(fixture.source.browser.shownTab?.id, fixture.tabID)
        XCTAssertFalse(fixture.root.sidebarInteraction.sidebarReorderState.hasLiftInFlight)
    }

    @MainActor
    private final class Fixture {
        let coordinator: BrowserMacWindowCoordinator
        let source: BrowserMacWindowModel
        let root: BrowserRootModel
        let input: BrowserNativeMouseInput
        let tabID: UUID
        let destinationWindow: NSWindow
        private(set) var outside = CGPoint(x: 1_320, y: -120)
        var request: BrowserMacWindowRequest?
        var capturedDropPoint: CGPoint?
        var capturedGrabFraction: CGPoint?
        var measuredDestinationRow: BrowserSidebarReorderRow?
        var completedPlacementFromRow = false

        init() throws {
            let tab = TabState.Seed(title: "Tear off", url: URL(string: "about:blank"), placement: .current)
            tabID = tab.id
            let space = SpaceState.Seed(
                name: "Temporary windows", symbol: "globe",
                accent: .indigo, folders: [], tabs: [tab])
            let browser = BrowserStore.hostingPages(
                SessionState.Seed(spaces: [space]),
                showing: space.id, tabs: [space.id: tab.id])
            let access = BrowserSpaceAccessController()
            coordinator = BrowserMacWindowCoordinator(
                browser: browser,
                pages: BrowserPagePool(
                    browser: browser, usesEphemeralWebsiteDataStores: true),
                spaceAccess: access, windowLayouts: BrowserWindowLayouts(defaults: nil))
            source = try XCTUnwrap(coordinator.model(for: .initial))
            root = BrowserRootModel(
                browser: source.browser, pages: source.pages, chrome: source.chrome, spaceAccess: access,
                windowState: source.windowState, startupBehavior: .lastActiveTab,
                persistedSidebarWidth: BrowserChromeLayout.sidebarIdealWidth)
            let window = NSWindow(
                contentRect: CGRect(x: 80, y: 80, width: 1_160, height: 620),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            destinationWindow = NSWindow(
                contentRect: CGRect(x: 100, y: 100, width: 900, height: 600),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            destinationWindow.isReleasedWhenClosed = false
            input = BrowserNativeMouseInput(window: window)
            window.contentView = NSHostingView(
                rootView:
                    TearOffTestSurface(model: root)
                    .environment(root.sidebarInteraction)
                    .environment(
                        \.browserSidebarWindowDrop,
                        BrowserSidebarWindowDrop(
                            windowID: UUID(),
                            perform: { [weak self, weak window] lift in
                                guard let self, let window, let event = NSApp.currentEvent else { return false }
                                let point = window.convertPoint(toScreen: event.locationInWindow)
                                self.capturedDropPoint = point
                                self.capturedGrabFraction = lift.anchorFraction
                                return BrowserMacWindowDropAction(
                                    coordinator: self.coordinator, sourceWindowID: self.source.id,
                                    open: { [weak self] in self?.request = $0 }
                                ).perform(lift.item, at: point, grabFraction: lift.anchorFraction)
                            })))
            coordinator.attach(window, to: source.id)
            window.makeKeyAndOrderFront(nil)
            // The app's initial scene or an earlier test may have another
            // visible window. This fixture specifically exercises empty desktop.
            let rightEdge =
                NSApp.orderedWindows.filter { $0.isVisible && !$0.ignoresMouseEvents }
                .map { $0.frame.maxX }.max() ?? window.frame.maxX
            outside.x = rightEdge - window.frame.minX + 80
            pump()
        }

        func hostDestination(_ model: BrowserMacWindowModel) {
            let root = BrowserRootModel(
                browser: model.browser, pages: model.pages, chrome: model.chrome, spaceAccess: coordinator.spaceAccess,
                windowState: model.windowState, startupBehavior: .lastActiveTab,
                persistedSidebarWidth: BrowserChromeLayout.sidebarIdealWidth)
            destinationWindow.contentView = NSHostingView(
                rootView:
                    TearOffTestSurface(model: root)
                    .environment(root.sidebarInteraction)
                    .environment(
                        \.browserSidebarWindowDrop,
                        BrowserSidebarWindowDrop(
                            windowID: UUID(),
                            perform: { _ in false },
                            didMeasureRow: { [weak self, weak model] row in
                                guard let self, let model else { return }
                                if row.id == .tab(self.tabID) { self.measuredDestinationRow = row }
                                let wasPending = model.tearOffPlacement?.isPending == true
                                self.coordinator.didMeasureRow(row, in: model.id)
                                if wasPending, model.tearOffPlacement?.isPending == false {
                                    self.completedPlacementFromRow = true
                                }
                            })))
        }

        func drag(from row: CGRect, grabFraction: CGPoint = CGPoint(x: 0.5, y: 0.5)) {
            let start = CGPoint(
                x: row.minX + row.width * grabFraction.x, y: row.minY + row.height * grabFraction.y)
            input.send(.leftMouseDown, at: start)
            for step in 1...16 {
                let fraction = CGFloat(step) / 16
                input.send(
                    .leftMouseDragged,
                    at: CGPoint(
                        x: start.x + (outside.x - start.x) * fraction,
                        y: start.y + (outside.y - start.y) * fraction))
            }
        }

        func pump() { RunLoop.current.run(until: Date().addingTimeInterval(0.5)) }

        func close() {
            input.close()
            coordinator.closeWindow(source.id)
            if let request { coordinator.closeWindow(request.id) }
            destinationWindow.close()
        }
    }
}

private struct TearOffTestSurface: View {
    let model: BrowserRootModel
    @Namespace private var commandNamespace
    @Namespace private var tabNamespace
    @State private var sidebarWidth = Double(BrowserChromeLayout.sidebarIdealWidth)

    var body: some View {
        BrowserRootShell(
            model: model, transientBrowsing: BrowserTransientBrowsingCoordinator(),
            spaceSettingsPresentation: BrowserSpaceSettingsPresentationState(), shortcuts: nil,
            storedSidebarWidth: $sidebarWidth,
            commandSurfaceNamespace: commandNamespace, tabPromotionNamespace: tabNamespace)
    }
}
