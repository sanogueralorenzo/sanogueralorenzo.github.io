import AppKit
import XCTest

@testable import Crest

@MainActor
final class BrowserMacMouseButtonsTests: XCTestCase {
    // MARK: - Types

    /// A window's content that takes the presses it is offered while
    /// `takesPresses` says so.
    private final class Content: BrowserMacWindowPointerNavigation {
        var takesPresses: Bool
        private(set) var presses: [BrowserSidebarMouseButtonAction] = []

        init(takesPresses: Bool) {
            self.takesPresses = takesPresses
        }

        func takePress(_ action: BrowserSidebarMouseButtonAction, at event: NSEvent) -> Bool {
            presses.append(action)
            return takesPresses
        }

        func navigate(_ action: BrowserSidebarMouseButtonAction, swipedAt event: NSEvent) -> Bool {
            false
        }
    }

    /// A page that counts the times it was moved back, and the Space switches
    /// its window was asked for.
    private final class Page: BrowserSidebarMouseNavigationTarget {
        let nativeView = NSView()
        let live = PageLiveState(
            url: nil, pendingURL: nil, title: "", isLoading: false, canGoBack: true, canGoForward: false,
            security: .none, failure: nil, media: [], address: nil)
        private(set) var backs = 0
        private(set) var spaceSwitches: [BrowserSidebarMouseButtonAction] = []

        func goBack() { backs += 1 }
        func goForward() {}
        func switchSpace(_ action: BrowserSidebarMouseButtonAction) { spaceSwitches.append(action) }
    }

    // MARK: - Actions - Tests

    /// Logitech Options+ sends a mouse's Back button as a swipe, so a swipe
    /// over the sidebar switches Space as the button does, and one over a page
    /// still moves that page.
    func testSwipeSwitchesSpaceOverTheSidebarAndMovesThePageOverIt() throws {
        let window = BrowserMacWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.borderless],
            backing: .buffered, defer: false)
        defer { window.close() }
        window.isReleasedWhenClosed = false
        let page = Page()
        let sidebar = BrowserSidebarPointerNavigationView(
            perform: { page.switchSpace($0) }, navigationTargets: { [page] }, activeTarget: { page })
        let contentView = try XCTUnwrap(window.contentView)
        sidebar.frame = NSRect(x: 0, y: 0, width: 100, height: 200)
        page.nativeView.frame = NSRect(x: 100, y: 0, width: 300, height: 200)
        contentView.addSubview(sidebar)
        contentView.addSubview(page.nativeView)

        let overSidebar = try swipe(at: NSPoint(x: 50, y: 100), in: window)
        XCTAssertTrue(sidebar.navigate(.previousSpace, swipedAt: overSidebar))
        XCTAssertEqual(page.spaceSwitches, [.previousSpace])
        XCTAssertEqual(page.backs, 0)

        let overPage = try swipe(at: NSPoint(x: 250, y: 100), in: window)
        XCTAssertTrue(sidebar.navigate(.previousSpace, swipedAt: overPage))
        XCTAssertEqual(page.spaceSwitches, [.previousSpace])
        XCTAssertEqual(page.backs, 1)
    }

    /// Chromium goes back or forward again on a Back or Forward release it
    /// sees, so the release of a press Crest acted on must never reach the
    /// page, even when SwiftUI rebuilt the window's content in between.
    func testTakenClickIsTakenWholeAfterTheWindowContentIsRebuilt() throws {
        var content: Content? = Content(takesPresses: true)
        let buttons = BrowserMacMouseButtons(navigation: { _ in content })

        XCTAssertTrue(buttons.take(try event(.otherMouseDown, button: 3)))
        XCTAssertEqual(content?.presses, [.previousSpace])
        content = nil

        XCTAssertTrue(buttons.take(try event(.otherMouseDragged, button: 3)))
        XCTAssertTrue(buttons.take(try event(.otherMouseUp, button: 3)))
        XCTAssertFalse(buttons.take(try event(.otherMouseUp, button: 3)))
    }

    /// A click the window's content lets go reaches the page whole, even
    /// after a taken press whose release the application never saw.
    func testClickTheContentLetsGoReachesThePageWhole() throws {
        let content = Content(takesPresses: true)
        let buttons = BrowserMacMouseButtons(navigation: { _ in content })
        XCTAssertTrue(buttons.take(try event(.otherMouseDown, button: 4)))

        content.takesPresses = false
        XCTAssertFalse(buttons.take(try event(.otherMouseDown, button: 4)))
        XCTAssertFalse(buttons.take(try event(.otherMouseDragged, button: 4)))
        XCTAssertFalse(buttons.take(try event(.otherMouseUp, button: 4)))
        XCTAssertFalse(buttons.take(try event(.otherMouseDown, button: 2)))
        XCTAssertFalse(buttons.take(try event(.otherMouseUp, button: 2)))
        XCTAssertEqual(content.presses, [.nextSpace, .nextSpace])
    }

    // MARK: - Actions - Events

    private func event(_ type: CGEventType, button: Int64) throws -> NSEvent {
        let event = try XCTUnwrap(
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: .zero, mouseButton: .center))
        event.setIntegerValueField(.mouseEventButtonNumber, value: button)
        return try XCTUnwrap(NSEvent(cgEvent: event))
    }

    /// Stands in for a swipe at `location`: AppKit cannot build one, and the
    /// window answers a swipe only by where it happened.
    private func swipe(at location: NSPoint, in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .otherMouseDown, location: location, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }
}
