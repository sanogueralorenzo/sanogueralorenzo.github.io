import AppKit
import XCTest

@testable import Crest

@MainActor
final class BrowserNativeWindowInputTests: XCTestCase {
    func testBrowserChromeKeepsTheNativeTitleBarAndControls() throws {
        let window = makeWindow()
        defer { window.close() }
        let content = try XCTUnwrap(window.contentView)
        let buttons = BrowserNativeWindowControlsHostView.buttonTypes.compactMap(window.standardWindowButton)
        let input = NSTextField(frame: NSRect(x: 350, y: 560, width: 200, height: 28))
        content.addSubview(input)
        let chrome = BrowserNativeWindowControlsHostView()
        content.addSubview(chrome)
        window.layoutIfNeeded()

        // The window stays movable, so the system's window commands move it;
        // content under the title bar still receives its own clicks.
        XCTAssertTrue(window.isMovable)
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertTrue(content.hitTest(NSPoint(x: 400, y: 574)) === input)
        for (type, button) in zip(BrowserNativeWindowControlsHostView.buttonTypes, buttons) {
            XCTAssertTrue(window.standardWindowButton(type) === button)
            XCTAssertTrue(button.isEnabled)
        }

        chrome.isVisible = false
        chrome.sidebarOnRight = true
        chrome.applyBrowserChrome()
        XCTAssertTrue(window.isMovable)
        XCTAssertTrue(content.hitTest(NSPoint(x: 400, y: 574)) === input)
    }

    func testAPageHoldsTheWindowStillOnlyWhileThePointerIsOnItsTop() throws {
        let window = makeWindow()
        defer { window.close() }
        let content = try XCTUnwrap(window.contentView)
        content.addSubview(BrowserNativeWindowControlsHostView())
        let page = NSView(frame: NSRect(x: 260, y: 0, width: 640, height: 600))
        content.addSubview(page)
        window.layoutIfNeeded()
        let tracker = BrowserPageTitleBarTracker(page: page)
        let titleBarBottom = window.contentLayoutRect.maxY
        XCTAssertLessThan(titleBarBottom, content.bounds.maxY)

        // On the page under the title bar, or on its way up to it, the window
        // server gets no strip to drag the window from.
        tracker.mouseMoved(with: try pointer(at: NSPoint(x: 500, y: titleBarBottom + 10), in: window))
        XCTAssertFalse(window.isMovable)
        tracker.mouseMoved(with: try pointer(at: NSPoint(x: 500, y: 200), in: window))
        XCTAssertTrue(window.isMovable)
        tracker.mouseMoved(with: try pointer(at: NSPoint(x: 500, y: titleBarBottom - 10), in: window))
        XCTAssertFalse(window.isMovable)

        // Anywhere else the window moves as any window does.
        tracker.mouseExited(with: try pointer(at: NSPoint(x: 100, y: titleBarBottom + 10), in: window))
        XCTAssertTrue(window.isMovable)
        tracker.mouseMoved(with: try pointer(at: NSPoint(x: 100, y: titleBarBottom + 10), in: window))
        XCTAssertTrue(window.isMovable)
    }

    func testLeavingAWindowKeepsTheFullscreenStateAppKitGaveIt() {
        let windowed: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        let chrome = windowed.union(.fullSizeContentView)

        XCTAssertEqual(
            chrome.union(.fullScreen).restoringBrowserChrome(to: windowed),
            windowed.union(.fullScreen))
        XCTAssertEqual(
            chrome.restoringBrowserChrome(to: windowed.union(.fullScreen)),
            windowed)
    }

    private func pointer(at location: NSPoint, in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .mouseMoved, location: location, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0
            ))
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }
}
