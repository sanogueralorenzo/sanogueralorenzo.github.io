import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserPageTranslationTests: XCTestCase {
    func testOffersDoNotTranslateUntilRequestedAndShowingOriginalEndsTheOperation() async throws {
        let web = try await fixture()
        let translation = BrowserPageTranslation()
        translation.setActive(true, in: BrowserTranslationDocument(webView: web))
        await translation.detect()
        XCTAssertNil(translation.configuration, "Detection must never request translation or a model download.")
        XCTAssertFalse(translation.isWorking)
        translation.updateTargetLanguage("fr")
        translation.start()
        XCTAssertNil(translation.configuration?.source)
        XCTAssertEqual(translation.configuration?.target?.languageCode?.identifier, "fr")
        XCTAssertNotNil(translation.configuration)
        translation.showOriginal()
        XCTAssertFalse(translation.isWorking, "Show Original must end the current translation.")
        XCTAssertNil(translation.configuration)
        translation.reset()
        XCTAssertFalse(translation.isOffered)
        XCTAssertNil(translation.configuration)
    }

    func testAutomaticTranslationHonorsPreferencesAndDoesNotUndoShowOriginal() async throws {
        let web = try await fixture()
        let translation = BrowserPageTranslation()
        translation.setActive(true, in: BrowserTranslationDocument(webView: web))
        translation.updateTargetLanguage("en")

        await translation.detect(automatically: true, excluding: ["es-MX"])
        XCTAssertEqual(translation.sourceID, "es")
        XCTAssertNil(translation.configuration, "Excluded languages must not request translation or model downloads.")
        translation.updateTargetLanguage("es-ES")
        await translation.detect(automatically: true)
        XCTAssertNil(translation.configuration, "Regional aliases of the target must not translate.")
        translation.updateTargetLanguage("en")
        await translation.detect(automatically: false)
        XCTAssertNil(translation.configuration)

        await translation.detect(automatically: true)
        XCTAssertNotNil(translation.configuration)
        XCTAssertTrue(translation.isWorking)
        translation.showOriginal()
        await translation.detect(automatically: true)
        XCTAssertNil(translation.configuration, "Show Original must last until navigation, including host remounts.")

        translation.reset()
        await translation.detect(automatically: true, excluding: ["es"])
        XCTAssertNil(translation.configuration)
        translation.performAction()
        XCTAssertNotNil(translation.configuration, "A manual request can translate an excluded language.")
        translation.reset()
        await translation.detect(automatically: true)
        XCTAssertNotNil(translation.configuration, "A new document can translate automatically again.")
        translation.reset()
    }

    func testDisappearingPreviousHostCannotCancelTheCurrentHostsTranslation() throws {
        let web = WKWebView()
        let translation = BrowserPageTranslation()
        let previousHost = UUID()
        let currentHost = UUID()
        translation.setActive(true, in: BrowserTranslationDocument(webView: web), hostID: previousHost)
        translation.updateTargetLanguage("en")
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
