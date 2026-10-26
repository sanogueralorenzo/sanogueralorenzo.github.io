import AppKit
import XCTest

@testable import Crest

@MainActor
final class BrowserNativeWindowInputTests: XCTestCase {
    func testAPageHoldsTheWindowStillOnlyWhileThePointerIsOnItsTop() throws {
        let window = makeWindow()
        defer { window.close() }
        let content = try XCTUnwrap(window.contentView)
        content.addSubview(BrowserNativeWindowControlsHostView())
        let page = NSView(frame: NSRect(x: 260, y: 0, width: 640, height: 600))
        content.addSubview(page)
        window.layoutIfNeeded()
        let tracker = BrowserTitleBarPointerTracker(view: page, region: .page)
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

    func testAControlUnderTheTitleBarHoldsTheWindowStillOnlyWhileThePointerIsOnIt() throws {
        let window = makeWindow()
        defer { window.close() }
        let content = try XCTUnwrap(window.contentView)
        content.addSubview(BrowserNativeWindowControlsHostView())
        window.layoutIfNeeded()
        let top = content.bounds.maxY
        let field = NSView(frame: NSRect(x: 100, y: top - 46, width: 400, height: 36))
        let lowerField = NSView(frame: NSRect(x: 100, y: 200, width: 400, height: 36))
        content.addSubview(field)
        content.addSubview(lowerField)
        let tracker = BrowserTitleBarPointerTracker(view: field, region: .control)
        let lowerTracker = BrowserTitleBarPointerTracker(view: lowerField, region: .control)
        XCTAssertLessThan(window.contentLayoutRect.maxY, top - 10)

        // A press on the field under the title bar reaches the field, so a
        // drag across its text selects it rather than moving the window.
        tracker.mouseEntered(with: try pointer(at: NSPoint(x: 300, y: top - 28), in: window))
        XCTAssertFalse(window.isMovable)

        // Off the field, or on a control below the title bar, the window
        // moves as any window does.
        tracker.mouseExited(with: try pointer(at: NSPoint(x: 700, y: top - 28), in: window))
        XCTAssertTrue(window.isMovable)
        lowerTracker.mouseEntered(with: try pointer(at: NSPoint(x: 300, y: 218), in: window))
        XCTAssertTrue(window.isMovable)
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
