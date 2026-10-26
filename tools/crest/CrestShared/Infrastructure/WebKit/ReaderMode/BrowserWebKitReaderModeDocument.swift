import WebKit

@MainActor
final class BrowserWebKitReaderModeDocument: BrowserReaderModeDocument {
    private let webView: WKWebView
    private let translation: BrowserPageTranslation

    init(webView: WKWebView, translation: BrowserPageTranslation) {
        self.webView = webView
        self.translation = translation
    }

    var url: URL? { webView.url }

    func prepareForReaderMode() async throws {
        try await translation.prepareForReaderMode()
    }

    func readerModeIsAvailable() async throws -> Bool {
        try await BrowserReaderModeController.isAvailable(in: webView)
    }

    func activateReaderMode() async throws {
        try await BrowserReaderModeController.activate(in: webView)
    }

    func deactivateReaderMode() async throws {
        try await BrowserReaderModeController.deactivate(in: webView)
    }
}
