import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserPictureInPicturePlayerTests: XCTestCase {
    func testPlayerEligibilityPermutations() async throws {
        let cases: [(String, String, String, Bool)] = [
            ("native controls", "<video controls></video>", "", true),
            ("muted native player", "<video controls muted loop autoplay></video>", "", true),
            ("decorative homepage", "<video autoplay muted loop></video>", "", false),
            (
                "background pause button",
                "<div><video autoplay muted loop></video><button>Pause animation</button></div>", "", false
            ),
            (
                "custom player",
                "<div><video></video><button>Play</button><button>Mute</button><input type=range></div>", "", true
            ),
            (
                "preview without timeline",
                "<div><video autoplay muted loop></video><button>Play</button><button>Mute</button></div>", "", false
            ),
            (
                "controls disabled by embed",
                "<div><video autoplay muted loop></video><div style='display:none'><button>Play</button><button>Mute</button><input type=range></div></div>",
                "", false
            ),
            (
                "unrelated page controls",
                "<video autoplay muted loop></video><button>Play</button><button>Mute</button><input type=range>", "",
                false
            ),
            ("transparent decoration", "<div style='opacity:0'><video controls></video></div>", "", false),
            ("pointer disabled decoration", "<video controls style='pointer-events:none'></video>", "", false),
            ("hidden from accessibility", "<div aria-hidden=true><video controls></video></div>", "", false),
            ("paused player", "<video controls></video>", "paused: true", false),
            ("ended player", "<video controls></video>", "ended: true", false),
            ("audio only media", "<video controls></video>", "videoHeight: 0", false),
            ("no metadata", "<video controls></video>", "readyState: 0", false),
            (
                "website disallows PiP", "<video controls disablepictureinpicture></video>",
                "disablePictureInPicture: true", false
            ),
            ("tiny video", "<video controls style='width:20px;height:20px'></video>", "", false),
            ("scrolled out", "<video controls style='position:absolute;top:10000px'></video>", "", false),
        ]
        for (name, html, overrides, expected) in cases {
            let webView = makeWebView()
            webView.loadHTMLString(
                "<style>video { width:640px;height:360px }</style>\(html)",
                baseURL: URL(string: "https://pip.crest.test"))
            try await waitForBridge(webView)
            let state = try await evaluate(
                mockPlayback(overrides: overrides) + "; globalThis.__crestPictureInPicture.snapshot()", in: webView)
            XCTAssertEqual((state as? [String: Any])?["eligible"] as? Bool, expected, name)
        }
    }

    func testSubframeReportsReachTheOwningWebView() async throws {
        let webView = makeWebView()
        let controller = BrowserPictureInPicturePageController(webView: webView)
        let mock = WKUserScript(
            source: mockPlayback() + "; document.querySelector('video')?.dispatchEvent(new Event('playing'));",
            injectionTime: .atDocumentEnd, forMainFrameOnly: false,
            in: BrowserPictureInPictureContentBridge.contentWorld)
        webView.configuration.userContentController.addUserScript(mock)
        webView.loadHTMLString(
            """
            <iframe style="width:700px;height:420px" srcdoc="<video controls style='width:640px;height:360px'></video>"></iframe>
            """, baseURL: URL(string: "https://pip.crest.test"))
        let deadline = Date().addingTimeInterval(5)
        while !controller.canAutomaticallyEnterPictureInPicture && Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(controller.canAutomaticallyEnterPictureInPicture)
        controller.invalidate()
        XCTAssertFalse(controller.canAutomaticallyEnterPictureInPicture)
        controller.returnToTab()
        try await waitForEligibility(true, controller: controller)
        controller.invalidate()
    }

    func testEmptyFrameWakesWhenPlaybackArrivesAndRetiresWhenReplaced() async throws {
        let webView = makeWebView()
        let controller = BrowserPictureInPicturePageController(webView: webView)
        defer { controller.invalidate() }
        webView.configuration.userContentController.addUserScript(
            WKUserScript(
                source: mockPlayback() + "; document.querySelector('video')?.dispatchEvent(new Event('playing'));",
                injectionTime: .atDocumentEnd, forMainFrameOnly: false,
                in: BrowserPictureInPictureContentBridge.contentWorld))
        webView.loadHTMLString(
            "<iframe style='width:700px;height:420px' srcdoc='<p>No media</p>'></iframe>",
            baseURL: URL(string: "https://pip.crest.test"))
        try await waitForBridge(webView)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(controller.canAutomaticallyEnterPictureInPicture)
        _ = try await evaluate(
            """
            document.querySelector('iframe').srcdoc = '<video controls style="width:640px;height:360px"></video>';
            true;
            """, in: webView)
        try await waitForEligibility(true, controller: controller)
        _ = try await evaluate("document.querySelector('iframe').srcdoc = '<p>No media</p>'; true", in: webView)
        try await waitForEligibility(false, controller: controller)
    }

    func testInsertedShadowPlayerAndAncestorVisibilityRemainObserved() async throws {
        for precedingElements in [0, 10_005] {
            let webView = makeWebView()
            let controller = BrowserPictureInPicturePageController(webView: webView)
            defer { controller.invalidate() }
            webView.loadHTMLString(
                "<body></body>",
                baseURL: URL(string: "https://pip.crest.test"))
            try await waitForBridge(webView)
            _ = try await evaluate(
                """
                (() => {
                  const host = document.createElement('div');
                  host.id = 'host';
                  host.attachShadow({mode:'open'});
                  document.body.append(host);
                  return true;
                })()
                """, in: webView)
            _ = try await evaluate(
                """
                const root = document.querySelector('#host').shadowRoot;
                const wrapper = document.createElement('div');
                root.append(wrapper);
                for (let index = 0; index < \(precedingElements); index++) {
                  wrapper.append(document.createElement('span'));
                }
                const video = document.createElement('video');
                video.controls = true;
                video.style.cssText = 'width:640px;height:360px';
                wrapper.append(video);
                for (const [key, value] of Object.entries({ paused: false, ended: false,
                    readyState: 4, videoWidth: 640, videoHeight: 360 })) {
                  Object.defineProperty(video, key, { configurable: true, value });
                }
                video.webkitSupportsPresentationMode = () => true;
                true;
                """, in: webView)
            try await waitForEligibility(true, controller: controller)
            _ = try await evaluate("document.querySelector('#host').style.opacity = '0'; true", in: webView)
            try await waitForEligibility(false, controller: controller)
            _ = try await evaluate("document.querySelector('#host').style.opacity = '1'; true", in: webView)
            try await waitForEligibility(true, controller: controller)
        }
    }

    private func waitForEligibility(
        _ expected: Bool, controller: BrowserPictureInPicturePageController
    ) async throws {
        let deadline = Date().addingTimeInterval(5)
        while controller.canAutomaticallyEnterPictureInPicture != expected && Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(controller.canAutomaticallyEnterPictureInPicture, expected)
    }

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        BrowserPictureInPictureContentBridge.shared.install(in: configuration.userContentController)
        return WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 700), configuration: configuration)
    }

    private func mockPlayback(overrides: String = "") -> String {
        """
        for (const video of document.querySelectorAll('video')) {
          const values = { paused: false, ended: false, readyState: 4, videoWidth: 640, videoHeight: 360, \(overrides) };
          for (const [key, value] of Object.entries(values)) Object.defineProperty(video, key, { configurable: true, value });
          video.webkitSupportsPresentationMode = () => true;
        }
        """
    }

    private func evaluate(_ script: String, in webView: WKWebView) async throws -> Any {
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script, in: nil, in: BrowserPictureInPictureContentBridge.contentWorld) {
                do {
                    let value = try $0.get()
                    let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
                    continuation.resume(returning: data)
                } catch { continuation.resume(throwing: error) }
            }
        }
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private func waitForBridge(_ webView: WKWebView) async throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if (try? await evaluate(
                "!!globalThis.__crestPictureInPicture && document.readyState === 'complete'", in: webView)) as? Bool
                == true
            {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("PiP fixture did not load")
    }
}
