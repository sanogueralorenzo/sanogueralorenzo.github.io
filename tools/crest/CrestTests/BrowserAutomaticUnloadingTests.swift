import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserAutomaticUnloadingTests: XCTestCase {
    func testAutomaticUnloadProtectsEditedFormsAndExplicitBeforeUnloadHandlers() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 480), configuration: configuration)
        let engine = BrowserWebKitPageEngine(webView: webView)
        webView.loadHTMLString(
            "<input id='draft'><textarea id='note'></textarea>", baseURL: URL(string: "https://idle.crest.test"))
        for _ in 0..<200 {
            if !webView.isLoading,
                (try? await webView.evaluateJavaScript("document.readyState")) as? String == "complete"
            {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let clean = await engine.canAutomaticallyUnload()
        XCTAssertTrue(clean)
        try await webView.evaluateJavaScript("document.getElementById('draft').value='unsaved'; true")
        let editedInput = await engine.canAutomaticallyUnload()
        XCTAssertFalse(editedInput)
        try await webView.evaluateJavaScript(
            "document.getElementById('draft').value=''; document.getElementById('note').value='draft'; true")
        let editedNote = await engine.canAutomaticallyUnload()
        XCTAssertFalse(editedNote)
        try await webView.evaluateJavaScript(
            "document.getElementById('note').value=''; window.onbeforeunload=()=>''; true")
        let guarded = await engine.canAutomaticallyUnload()
        XCTAssertFalse(guarded)
        try await webView.evaluateJavaScript("window.onbeforeunload=null; true")
        let reset = await engine.canAutomaticallyUnload()
        XCTAssertTrue(reset)
    }
}
