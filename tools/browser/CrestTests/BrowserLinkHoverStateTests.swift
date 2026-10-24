import Foundation
import WebKit
import XCTest

@testable import Crest

final class BrowserLinkHoverStateTests: XCTestCase {
    func testBridgeContractRejectsUnboundedAndMalformedReports() {
        let valid: [String: Any] = [
            "version": 1, "document": "frame", "sequence": 2, "href": "https://example.test/path",
        ]
        XCTAssertEqual(BrowserLinkHoverMessage(body: valid)?.href, "https://example.test/path")
        var body = valid
        body["href"] = NSNull()
        XCTAssertNotNil(BrowserLinkHoverMessage(body: body))
        XCTAssertNil(BrowserLinkHoverMessage(body: body)?.href)
        for invalid in ["href": 17, "version": 2, "document": String(repeating: "a", count: 129), "sequence": -1]
            as [String: Any]
        {
            var malformed = valid
            malformed[invalid.key] = invalid.value
            XCTAssertNil(BrowserLinkHoverMessage(body: malformed))
        }
        body["href"] = String(repeating: "é", count: 4_097)
        XCTAssertNil(BrowserLinkHoverMessage(body: body))
        body = valid
        body["unexpected"] = "value"
        XCTAssertNil(BrowserLinkHoverMessage(body: body))
    }

    func testInitialDwellAndExpansionHaveSeparateDeadlines() {
        var state = BrowserLinkHoverState()
        let ticket = state.receive(document: "main", sequence: 1, href: "https://example.test/path?q=1#part", at: 10)
        XCTAssertNil(state.destination)
        XCTAssertFalse(state.reveal(ticket: ticket, at: 10.16))
        XCTAssertFalse(state.reveal(ticket: ticket, at: 10.99))
        XCTAssertTrue(state.reveal(ticket: ticket, at: 11))
        XCTAssertEqual(state.destination?.text, "https://example.test/path?q=1#part")
        XCTAssertFalse(state.expand(ticket: ticket, at: 11.79))
        XCTAssertTrue(state.expand(ticket: ticket, at: 11.8))
        XCTAssertTrue(state.isExpanded)
    }

    func testAChangedTargetCannotRevealItsPredecessor() {
        var state = BrowserLinkHoverState()
        let first = state.receive(document: "main", sequence: 1, href: "https://example.test/one", at: 0)
        let second = state.receive(document: "main", sequence: 2, href: "https://example.test/two", at: 0.1)
        XCTAssertFalse(state.reveal(ticket: first, at: 1))
        XCTAssertFalse(state.reveal(ticket: second, at: 1))
        XCTAssertTrue(state.reveal(ticket: second, at: 1.1))
        XCTAssertEqual(state.destination?.text, "https://example.test/two")
    }

    func testLeaveNavigationAndDetachmentRetireDelayedWork() {
        var state = BrowserLinkHoverState()
        let ticket = state.receive(document: "frame", sequence: 1, href: "https://example.test/old", at: 0)
        state.invalidate()
        XCTAssertFalse(state.reveal(ticket: ticket, at: 1))
        XCTAssertFalse(state.expand(ticket: ticket, at: 2))
        XCTAssertNil(state.destination)
        XCTAssertFalse(state.isExpanded)
    }

    func testAStaleFrameCannotClearAnotherFramesPreview() {
        var state = BrowserLinkHoverState()
        _ = state.receive(document: "frame-a", sequence: 1, href: "https://example.test/a", at: 0)
        let current = state.receive(document: "frame-b", sequence: 1, href: "https://example.test/b", at: 1)
        state.leave(document: "frame-a", sequence: 2)
        XCTAssertTrue(state.reveal(ticket: current, at: 2))
        XCTAssertEqual(state.destination?.text, "https://example.test/b")
        state.leave(document: "frame-b", sequence: 2)
        XCTAssertNil(state.destination)
    }

    func testNoLinkAndMalformedDestinationHaveNoPreview() {
        var state = BrowserLinkHoverState()
        let ticket = state.receive(document: "main", sequence: 1, href: nil, at: 0)
        XCTAssertFalse(state.reveal(ticket: ticket, at: 1))
        XCTAssertNil(state.destination)
        XCTAssertNil(BrowserLinkHoverDestination(resolvedURL: "relative/path"))
        XCTAssertNil(BrowserLinkHoverDestination(resolvedURL: String(repeating: "x", count: 8_193)))
    }

    func testDestinationPreservesPathQueryFragmentAndRemovesCredentials() {
        let destination = BrowserLinkHoverDestination(
            resolvedURL: "https://alice:secret@example.test:8443/a%20b?q=one%2Ftwo#part")
        XCTAssertEqual(destination?.text, "https://example.test:8443/a%20b?q=one%2Ftwo#part")
    }

    func testInternationalHostAndDirectionalControlsStayUnambiguous() {
        let destination = BrowserLinkHoverDestination(
            resolvedURL: "https://bücher.example/a\u{202E}txt?q=%E2%80%AE#end")
        XCTAssertEqual(destination?.text, "https://xn--bcher-kva.example/a%E2%80%AEtxt?q=%E2%80%AE#end")
        XCTAssertFalse(destination?.text.contains("\u{202E}") ?? true)
    }

    func testNonWebSchemesAreOnlyDestinationText() {
        XCTAssertEqual(
            BrowserLinkHoverDestination(resolvedURL: "mailto:test@example.test?subject=Hello")?.text,
            "mailto:test@example.test?subject=Hello")
        XCTAssertEqual(BrowserLinkHoverDestination(resolvedURL: "javascript:void(0)")?.text, "javascript:void(0)")
    }
}

@MainActor
final class BrowserLinkHoverBridgeTests: XCTestCase {
    func testBridgeLivesOutsidePageWorldAndIgnoresSyntheticPointerEvents() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let controller = configuration.userContentController
        BrowserLinkHoverContentBridge.install(in: controller)
        controller.removeScriptMessageHandler(
            forName: BrowserLinkHoverContentBridge.name, contentWorld: BrowserLinkHoverContentBridge.world)
        let recorder = HoverMessageRecorder()
        controller.add(
            recorder, contentWorld: BrowserLinkHoverContentBridge.world, name: BrowserLinkHoverContentBridge.name)
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 600, height: 400), configuration: configuration)
        let ready = expectation(description: "Fixture loaded")
        recorder.ready = ready
        webView.navigationDelegate = recorder
        webView.loadHTMLString(
            "<a href='https://example.test/never-requested'>Link</a><input id='editor'>",
            baseURL: URL(string: "https://fixture.test"))
        await fulfillment(of: [ready], timeout: 5)

        let pageWorld = try await webView.evaluateJavaScript("typeof globalThis.__crestLinkHover")
        XCTAssertEqual(pageWorld as? String, "undefined")
        let isolatedWorld = try await webView.callAsyncJavaScript(
            "return typeof globalThis.__crestLinkHover;", in: nil, contentWorld: BrowserLinkHoverContentBridge.world)
        XCTAssertEqual(isolatedWorld as? String, "object")
        _ = try await webView.evaluateJavaScript(
            """
            document.querySelector('#editor').focus();
            document.querySelector('a').dispatchEvent(new PointerEvent('pointerover', {bubbles:true, pointerType:'mouse', clientX:10, clientY:10}));
            document.querySelector('a').dispatchEvent(new PointerEvent('pointermove', {bubbles:true, pointerType:'mouse', clientX:10, clientY:10}));
            """)
        let active = try await webView.evaluateJavaScript("document.activeElement.id")
        XCTAssertEqual(active as? String, "editor")
        XCTAssertTrue(recorder.messages.isEmpty)
        XCTAssertEqual(recorder.navigationCount, 1)
        let stale = try await webView.callAsyncJavaScript(
            "return globalThis.__crestLinkHover.validate('old-document', 1, 'https://example.test/never-requested');",
            in: nil, contentWorld: BrowserLinkHoverContentBridge.world)
        XCTAssertEqual(stale as? Bool, false)
        webView.navigationDelegate = nil
        controller.removeScriptMessageHandler(
            forName: BrowserLinkHoverContentBridge.name, contentWorld: BrowserLinkHoverContentBridge.world)
    }

    func testPopupControllerSharesOneStatelessHoverBridge() {
        let controller = WKUserContentController()
        BrowserLinkHoverContentBridge.install(in: controller)
        XCTAssertEqual(controller.userScripts.count, 1)
        XCTAssertFalse(controller.userScripts[0].isForMainFrameOnly)
        XCTAssertEqual(controller.userScripts[0].injectionTime, .atDocumentStart)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let copied = configuration.copy() as? WKWebViewConfiguration
        XCTAssertTrue(copied?.userContentController === controller)
    }
}

@MainActor
private final class HoverMessageRecorder: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var messages: [WKScriptMessage] = []
    var ready: XCTestExpectation?
    var navigationCount = 0

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        messages.append(message)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        navigationCount += 1
        ready?.fulfill()
        ready = nil
    }
}
