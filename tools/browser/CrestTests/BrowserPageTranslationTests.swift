import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserPageTranslationTests: XCTestCase {
    func testOffersDoNotTranslateUntilRequestedAndShowingOriginalSuppressesAutomaticRetry() async throws {
        let web = try await fixture()
        let translation = BrowserPageTranslation()
        translation.setActive(true, in: BrowserTranslationDocument(webView: web))
        await translation.detect()
        await translation.automaticallyTranslateIfAvailable(enabled: false)
        XCTAssertNil(translation.configuration, "Detection must never request translation or a model download.")
        XCTAssertFalse(translation.isWorking)
        translation.dismiss()
        translation.targetID = "en"
        translation.start()
        XCTAssertTrue(translation.showsToolbar, "Starting from Page Actions must reveal translation controls.")
        XCTAssertNotNil(translation.configuration)
        translation.showOriginal()
        await translation.automaticallyTranslateIfAvailable(enabled: true)
        XCTAssertFalse(translation.isWorking, "Show Original must suppress automatic translation for this document.")
        XCTAssertNil(translation.configuration)
        translation.reset()
        XCTAssertFalse(translation.isOffered)
        XCTAssertNil(translation.configuration)
    }

    func testDisappearingPreviousHostCannotCancelTheCurrentHostsTranslation() throws {
        let web = WKWebView()
        let translation = BrowserPageTranslation()
        let previousHost = UUID()
        let currentHost = UUID()
        translation.setActive(true, in: BrowserTranslationDocument(webView: web), hostID: previousHost)
        translation.sourceID = "es"
        translation.targetID = "en"
        translation.start()
        let configuration = try XCTUnwrap(translation.configuration)

        translation.setActive(true, in: BrowserTranslationDocument(webView: web), hostID: currentHost)
        translation.setActive(false, in: BrowserTranslationDocument(webView: web), hostID: previousHost)

        XCTAssertTrue(translation.isWorking)
        XCTAssertEqual(translation.configuration, configuration)
        translation.setActive(false, in: BrowserTranslationDocument(webView: web), hostID: currentHost)
        XCTAssertFalse(translation.isWorking)
        XCTAssertNil(translation.configuration)
    }

    func testTranslationPreservesEditableContentAndWebsiteChangesOnRestore() async throws {
        let web = try await fixture()
        let capture = try await BrowserTranslationDocument(webView: web).capture(token: "first")
        XCTAssertTrue(capture.texts.contains("Hola mundo"))
        XCTAssertTrue(capture.texts.contains("Enviar"))
        XCTAssertFalse(capture.texts.contains("secret"))
        XCTAssertFalse(capture.texts.contains("no traducir"))
        let translated = capture.texts.enumerated().reversed().map {
            BrowserTranslationDocument.Update(index: $0.offset, text: "Translated " + $0.element)
        }
        _ = try await BrowserTranslationDocument(webView: web).apply(translated, token: "first")
        let heading = try await web.evaluateJavaScript("document.querySelector('h1').textContent") as? String
        XCTAssertEqual(heading, "Translated Hola mundo", "Streamed responses can arrive out of document order.")
        _ = try await web.evaluateJavaScript(
            "document.querySelector('input').value='edited'; document.querySelector('#live').firstChild.data='Site update';"
        )
        try await BrowserTranslationDocument(webView: web).restore(token: "first")
        let values =
            try await web.evaluateJavaScript(
                "[document.querySelector('h1').textContent,document.querySelector('input').value,document.querySelector('#live').textContent,document.querySelector('a').getAttribute('href')]"
            ) as? [String]
        XCTAssertEqual(values, ["Hola mundo", "edited", "Site update", "#next"])
    }

    func testRetiredOperationCannotApplyOrRestoreOverANewerTranslation() async throws {
        let web = try await fixture()
        let first = try await BrowserTranslationDocument(webView: web).capture(token: "first")
        let second = try await BrowserTranslationDocument(webView: web).capture(token: "second")
        let stale = try await apply(first.texts.map { _ in "Stale" }, token: "first", in: web)
        XCTAssertEqual(stale, 0)
        _ = try await apply(second.texts.map { _ in "Current" }, token: "second", in: web)
        try await BrowserTranslationDocument(webView: web).restore(token: "first")
        let heading = try await web.evaluateJavaScript("document.querySelector('h1').textContent") as? String
        XCTAssertEqual(heading, "Current")
        try await BrowserTranslationDocument(webView: web).restore(token: "second")
    }

    func testPageHideRestoresTextBeforeTheDocumentCanBeCached() async throws {
        let web = try await fixture()
        let capture = try await BrowserTranslationDocument(webView: web).capture(token: "cached")
        _ = try await apply(capture.texts.map { _ in "Translated" }, token: "cached", in: web)
        _ = try await web.evaluateJavaScript(
            "window.dispatchEvent(new PageTransitionEvent('pagehide', {persisted:true}))")
        let heading = try await web.evaluateJavaScript("document.querySelector('h1').textContent") as? String
        XCTAssertEqual(heading, "Hola mundo")
        let late = try await apply(capture.texts, token: "cached", in: web)
        XCTAssertEqual(late, 0)
    }

    func testNewDocumentRejectsOldResultsEvenAtTheSameURL() async throws {
        let web = try await fixture()
        let capture = try await BrowserTranslationDocument(webView: web).capture(token: "old")
        web.loadHTMLString("<h1>New document</h1>", baseURL: URL(string: "https://translation.crest.test"))
        try await waitForLoad(web)
        let applied = try await apply(capture.texts, token: "old", in: web)
        XCTAssertEqual(applied, 0)
    }

    func testRouteChangeRejectsLateResultsButAnchorNavigationKeepsTranslation() async throws {
        let web = try await fixture()
        let capture = try await BrowserTranslationDocument(webView: web).capture(token: "route")
        _ = try await web.evaluateJavaScript("history.pushState({}, '', '#next')")
        let applied = try await apply(capture.texts.map { _ in "Translated" }, token: "route", in: web)
        XCTAssertEqual(applied, capture.texts.count)
        try await BrowserTranslationDocument(webView: web).restore(token: "route")
        _ = try await BrowserTranslationDocument(webView: web).capture(token: "route-two")
        _ = try await web.evaluateJavaScript("history.pushState({}, '', '/new-route')")
        let stale = try await apply(capture.texts.map { _ in "Stale" }, token: "route-two", in: web)
        XCTAssertEqual(stale, 0)
    }

    func testDetectionSamplesBoundedTextWithoutChangingTheDocument() async throws {
        let web = try await fixture()
        _ = try await web.evaluateJavaScript("document.querySelector('h1').textContent = 'hola '.repeat(1500)")
        let sample = try await BrowserTranslationDocument(webView: web).sample()
        XCTAssertLessThanOrEqual(sample.text.count, 3000)
        XCTAssertFalse(sample.text.contains("secret"))
        let heading = try await web.evaluateJavaScript("document.querySelector('h1').textContent.length") as? Int
        XCTAssertEqual(heading, 7500)
        let capture = try await BrowserTranslationDocument(webView: web).capture(token: "large")
        XCTAssertTrue(capture.isLimited)
    }

    /// Applies `texts` to the captured entries in document order.
    private func apply(_ texts: [String], token: String, in web: WKWebView) async throws -> Int {
        try await BrowserTranslationDocument(webView: web).apply(
            texts.enumerated().map { BrowserTranslationDocument.Update(index: $0.offset, text: $0.element) },
            token: token)
    }

    private func fixture() async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        web.loadHTMLString(
            """
            <html lang="es"><body><h1>Hola mundo</h1><p id="live">Noticias nuevas</p>
            <a href="#next">Continuar</a><label>Nombre<input value="secret"></label>
            <textarea>secret</textarea><div contenteditable>secret</div><button>Enviar</button>
            <p translate="no">no traducir</p><p hidden>secret</p><script>const secret = 'secret';</script>
            </body></html>
            """, baseURL: URL(string: "https://translation.crest.test"))
        try await waitForLoad(web)
        return web
    }

    private func waitForLoad(_ web: WKWebView) async throws {
        for _ in 0..<100 {
            if !web.isLoading, (try? await web.evaluateJavaScript("document.readyState")) as? String == "complete" {
                return
            }
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTFail("Translation fixture did not load")
    }
}
