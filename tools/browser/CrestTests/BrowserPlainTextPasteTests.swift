import AppKit
import ObjectiveC
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserPlainTextPasteTests: XCTestCase {
    func testPlainTextPasteReachesWebKitsOwnHandlerWithoutRecursing() {
        let webView = BrowserDesktopWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let selector = Selector(("pasteAsPlainText:"))

        XCTAssertEqual(BrowserPlainTextPaste(for: webView)?.selector, selector)
        XCTAssertEqual(
            class_getInstanceMethod(BrowserDesktopWebView.self, selector),
            class_getInstanceMethod(WKWebView.self, selector),
            "Crest's page view must not override WebKit's paste, or the paste would re-enter it."
        )
        BrowserPlainTextPaste(for: webView)?.perform()
    }

    func testPlainTextPasteUsesChromiumsSelectorAndNeedsAResponderThatCanPaste() {
        let chromium = ChromiumStandInView()
        XCTAssertEqual(BrowserPlainTextPaste(for: chromium)?.selector, Selector(("pasteAndMatchStyle:")))
        BrowserPlainTextPaste(for: chromium)?.perform()
        XCTAssertEqual(chromium.pasted, 1)

        chromium.canPaste = false
        XCTAssertNil(BrowserPlainTextPaste(for: chromium), "A page with no editable focus disables the command.")
        XCTAssertNil(BrowserPlainTextPaste(for: NSView()), "A responder with neither selector disables it.")
    }
}

/// Stands in for Chromium's page view, which answers `pasteAndMatchStyle:`
/// and validates it against whether the page has editable focus.
private final class ChromiumStandInView: NSView, NSUserInterfaceValidations {
    var canPaste = true
    private(set) var pasted = 0

    @objc func pasteAndMatchStyle(_ sender: Any?) { pasted += 1 }

    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool { canPaste }
}
