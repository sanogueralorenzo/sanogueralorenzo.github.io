import AppKit
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserWebHostViewTests: XCTestCase {
    func testWebKeyFallbackPreservesAnExistingNativeHandlerAndRepeat() throws {
        let setup = focusHostSetup()
        let handler = BrowserKeyboardHandlerProbe()
        let terminal = BrowserKeyboardTerminalProbe()
        setup.host.nextResponder = handler
        handler.nextResponder = terminal
        XCTAssertTrue(setup.window.makeFirstResponder(setup.webView))
        let event = try keyboardFallbackEvent(in: setup.window, isRepeat: true)

        setup.host.keyDown(with: event)

        XCTAssertEqual(handler.events.count, 1)
        XCTAssertTrue(handler.events.first === event)
        XCTAssertTrue(terminal.unhandledSelectors.isEmpty)
        XCTAssertTrue(handler.nextResponder === terminal)
        XCTAssertNil(terminal.nextResponder)
    }

    /// A page sees a shortcut before Crest only while focus is in the page's
    /// own view; Crest's views beside it keep Crest's shortcuts first.
    func testOnlyThePageViewAndViewsInsideItArePageContent() {
        let setup = focusHostSetup()
        let inside = NSView()
        setup.webView.addSubview(inside)
        let field = NSTextField(string: "Native field")
        setup.host.addSubview(field)

        XCTAssertTrue(BrowserWebHostView.isPageContent(setup.webView))
        XCTAssertTrue(BrowserWebHostView.isPageContent(inside))
        XCTAssertFalse(BrowserWebHostView.isPageContent(setup.host))
        XCTAssertFalse(BrowserWebHostView.isPageContent(field))
        XCTAssertFalse(BrowserWebHostView.isPageContent(setup.window))
        XCTAssertFalse(BrowserWebHostView.isPageContent(nil))
    }

    private func keyboardFallbackEvent(
        in window: NSWindow,
        type: NSEvent.EventType = .keyDown,
        isRepeat: Bool = false
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: type,
                location: .zero,
                modifierFlags: [],
                timestamp: 1,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "z",
                charactersIgnoringModifiers: "z",
                isARepeat: isRepeat,
                keyCode: 6
            )
        )
    }

    func testFocusPolicyRequiresAPermittedOwnerAndNoCompetingPresentation() {
        let allowed = BrowserWebFocusRestorationGate(
            browserChromeOwnsFocus: false,
            pageChromeOwnsFocus: false
        )

        XCTAssertTrue(
            restorationPolicyAllows(gate: allowed)
        )
        XCTAssertFalse(
            restorationPolicyAllows(
                gate: BrowserWebFocusRestorationGate(
                    browserChromeOwnsFocus: true,
                    pageChromeOwnsFocus: false
                )
            )
        )
        XCTAssertFalse(
            restorationPolicyAllows(
                gate: BrowserWebFocusRestorationGate(
                    browserChromeOwnsFocus: false,
                    pageChromeOwnsFocus: true
                )
            )
        )
        XCTAssertFalse(
            restorationPolicyAllows(gate: allowed, currentOwner: .other)
        )
        XCTAssertTrue(
            restorationPolicyAllows(
                gate: allowed,
                currentOwner: .departingWebContent
            )
        )
        XCTAssertFalse(
            restorationPolicyAllows(gate: allowed, windowHasAttachedSheet: true)
        )
        XCTAssertFalse(
            restorationPolicyAllows(gate: allowed, menuIsTracking: true)
        )
        XCTAssertFalse(
            restorationPolicyAllows(gate: allowed, accessibilityOwnsFocus: true)
        )
        XCTAssertFalse(
            restorationPolicyAllows(gate: allowed, windowIsKey: false)
        )
        XCTAssertFalse(
            restorationPolicyAllows(gate: allowed, applicationIsActive: false)
        )
    }

    private func restorationPolicyAllows(
        gate: BrowserWebFocusRestorationGate,
        currentOwner: BrowserWebFocusRestorationCurrentOwner = .neutral,
        windowHasAttachedSheet: Bool = false,
        menuIsTracking: Bool = false,
        accessibilityOwnsFocus: Bool = false,
        windowIsKey: Bool = true,
        applicationIsActive: Bool = true
    ) -> Bool {
        gate.allowsRestoration(
            hasPendingCandidate: true,
            candidateBelongsToWebView: true,
            windowIsKey: windowIsKey,
            applicationIsActive: applicationIsActive,
            windowHasAttachedSheet: windowHasAttachedSheet,
            menuIsTracking: menuIsTracking,
            accessibilityOwnsFocus: accessibilityOwnsFocus,
            currentOwner: currentOwner
        )
    }

    private func focusHostSetup(window providedWindow: NSWindow? = nil) -> FocusHostSetup {
        let host = BrowserWebHostView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480)
        )
        let window =
            providedWindow
            ?? NSWindow(
                contentRect: host.frame,
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
        let webView = BrowserDesktopWebView(
            frame: host.bounds,
            configuration: WKWebViewConfiguration()
        )
        let controller = BrowserWebFocusRestorationController(webView: webView)
        webView.focusRestoration = controller
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        host.attach(webView, focusRestoration: controller)
        addTeardownBlock {
            window.orderOut(nil)
            host.detach()
        }
        return FocusHostSetup(
            window: window,
            host: host,
            webView: webView,
            controller: controller
        )
    }
}

@MainActor
private final class BrowserKeyboardTerminalProbe: NSResponder {
    var unhandledSelectors: [Selector] = []

    override func noResponder(for eventSelector: Selector) {
        unhandledSelectors.append(eventSelector)
    }
}

@MainActor
private final class BrowserKeyboardHandlerProbe: NSResponder {
    var events: [NSEvent] = []
    var onKeyDown: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        events.append(event)
        onKeyDown?()
    }
}

private struct FocusHostSetup {
    let window: NSWindow
    let host: BrowserWebHostView
    let webView: WKWebView
    let controller: BrowserWebFocusRestorationController
}
