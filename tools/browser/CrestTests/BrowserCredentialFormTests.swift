import Foundation
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserCredentialFormTests: XCTestCase {
    func testFocusMessageRequiresATrustedGestureAndNeverAcceptsAPassword() throws {
        let valid = try XCTUnwrap(
            BrowserCredentialFormMessage(body: [
                "version": 1,
                "event": "focus",
                "trusted": true,
                "formID": "form-1",
                "username": "person@example.com",
                "passwordKind": "current",
            ]))

        XCTAssertEqual(valid.event, .focus)
        XCTAssertEqual(valid.formID, "form-1")
        XCTAssertEqual(valid.username, "person@example.com")
        XCTAssertNil(valid.password)
        XCTAssertNil(
            BrowserCredentialFormMessage(body: [
                "version": 1,
                "event": "focus",
                "trusted": false,
                "formID": "form-1",
            ]))
        XCTAssertNil(
            BrowserCredentialFormMessage(body: [
                "version": 1,
                "event": "focus",
                "trusted": true,
                "formID": "form-1",
            ]))
        XCTAssertNil(
            BrowserCredentialFormMessage(body: [
                "version": 1,
                "event": "focus",
                "trusted": true,
                "formID": "form-1",
                "password": "page-tried-to-exfiltrate-this",
            ]))
    }

    func testSubmitMessageRequiresCompleteTrustedFieldsAndRedactsItsSecret() throws {
        let message = try XCTUnwrap(
            BrowserCredentialFormMessage(body: [
                "version": 1,
                "event": "submit",
                "trusted": true,
                "formID": "form-7",
                "username": "person",
                "password": "correct horse battery staple",
                "passwordKind": "new",
            ]))

        XCTAssertEqual(message.event, .submit)
        XCTAssertEqual(message.username, "person")
        XCTAssertEqual(message.password, "correct horse battery staple")
        XCTAssertEqual(message.passwordKind, .new)
        XCTAssertFalse(message.description.contains("correct horse battery staple"))
        XCTAssertTrue(message.description.contains("<redacted>"))

        XCTAssertNil(
            BrowserCredentialFormMessage(body: [
                "version": 1,
                "event": "submit",
                "trusted": false,
                "formID": "form-7",
                "username": "person",
                "password": "secret",
                "passwordKind": "current",
            ]))
        let passwordOnlyStep = try XCTUnwrap(
            BrowserCredentialFormMessage(body: [
                "version": 1,
                "event": "submit",
                "trusted": true,
                "formID": "form-7",
                "password": "secret",
                "passwordKind": "current",
            ]))
        XCTAssertNil(passwordOnlyStep.username)
        XCTAssertEqual(passwordOnlyStep.password, "secret")
    }

    func testDocumentStateContractDoesNotAcceptCredentialFields() throws {
        let state = try XCTUnwrap(
            BrowserCredentialFormMessage(body: [
                "version": 1,
                "event": "documentState",
                "trusted": false,
                "hasVisiblePasswordField": false,
            ]))
        XCTAssertEqual(state.hasVisiblePasswordField, false)

        XCTAssertNil(
            BrowserCredentialFormMessage(body: [
                "version": 1,
                "event": "documentState",
                "hasVisiblePasswordField": false,
                "username": "unexpected",
            ]))
        XCTAssertNil(
            BrowserCredentialFormMessage(body: [
                "version": 2,
                "event": "documentState",
                "hasVisiblePasswordField": false,
            ]))
    }

    func testMessageContractRejectsUnboundedFormAndCredentialValues() {
        XCTAssertNil(
            BrowserCredentialFormMessage(body: [
                "version": 1,
                "event": "focus",
                "trusted": true,
                "formID": String(repeating: "f", count: 257),
            ]))
        XCTAssertNil(
            BrowserCredentialFormMessage(body: [
                "version": 1,
                "event": "submit",
                "trusted": true,
                "formID": "form-1",
                "username": String(repeating: "u", count: 1_025),
                "password": "secret",
                "passwordKind": "current",
            ]))
        XCTAssertNil(
            BrowserCredentialFormMessage(body: [
                "version": 1,
                "event": "submit",
                "trusted": true,
                "formID": "form-1",
                "username": "person",
                "password": String(repeating: "p", count: 16_385),
                "passwordKind": "current",
            ]))
    }

    func testSaveCandidateNeverDescribesItsPassword() throws {
        let origin = try XCTUnwrap(CredentialOrigin(url: URL(string: "https://example.com/login")!))
        let candidate = BrowserCredentialSaveCandidate(
            id: UUID(),
            origin: origin,
            topLevelOrigin: origin,
            username: "person",
            password: "secret",
            passwordKind: .current,
            isCrossOriginFrame: false,
            submittedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertFalse(candidate.description.contains("secret"))
        XCTAssertFalse(candidate.debugDescription.contains("secret"))
    }

    func testSavePromptModelMovesFromCreateToSavedAndSuppressesTheIdenticalCandidate() async throws {
        let store = BrowserStore(
            seed: .preview,
            credentialVault: InMemoryCredentialVault()
        )
        let work = try XCTUnwrap(store.spaceModels.first)
        let submittedAt = Date(timeIntervalSince1970: 2_000)
        let origin = try XCTUnwrap(
            CredentialOrigin(url: try XCTUnwrap(URL(string: "https://accounts.crest.test/login")))
        )
        let candidate = BrowserCredentialSaveCandidate(
            id: UUID(),
            origin: origin,
            topLevelOrigin: origin,
            username: "person@example.com",
            password: "secret",
            passwordKind: .current,
            isCrossOriginFrame: false,
            submittedAt: submittedAt
        )
        let model = BrowserCredentialSavePromptModel()

        await model.prepare(
            candidate: candidate,
            in: work.id,
            browser: store,
            now: submittedAt
        )
        XCTAssertEqual(model.phase, .create)

        await model.commit(
            candidate: candidate,
            in: work.id,
            browser: store,
            now: submittedAt
        )
        XCTAssertEqual(model.phase, .saved(.created))

        let repeatedModel = BrowserCredentialSavePromptModel()
        await repeatedModel.prepare(
            candidate: candidate,
            in: work.id,
            browser: store,
            now: submittedAt
        )
        XCTAssertEqual(repeatedModel.phase, .alreadyStored)
    }

    func testSystemPasswordOfferRunsOnlyAfterCrestSaveAndRetriesWithoutDuplicatingIt() async throws {
        let store = BrowserStore(
            seed: .preview,
            credentialVault: InMemoryCredentialVault()
        )
        let work = try XCTUnwrap(store.spaceModels.first)
        let submittedAt = Date(timeIntervalSince1970: 2_100)
        let origin = try XCTUnwrap(
            CredentialOrigin(url: try XCTUnwrap(URL(string: "https://accounts.crest.test/login")))
        )
        let candidate = BrowserCredentialSaveCandidate(
            id: UUID(),
            origin: origin,
            topLevelOrigin: origin,
            username: "person@example.com",
            password: "secret",
            passwordKind: .current,
            isCrossOriginFrame: false,
            submittedAt: submittedAt
        )
        let model = BrowserCredentialSavePromptModel()
        var offerCount = 0

        await model.offerToSystemPasswords {
            offerCount += 1
        }
        XCTAssertEqual(offerCount, 0)
        XCTAssertEqual(model.systemPasswordOfferPhase, .notRequested)

        await model.prepare(
            candidate: candidate,
            in: work.id,
            browser: store,
            now: submittedAt
        )
        await model.commit(
            candidate: candidate,
            in: work.id,
            browser: store,
            now: submittedAt
        )
        await model.offerToSystemPasswords {
            offerCount += 1
            throw TestSystemPasswordOfferError.rejected
        }

        XCTAssertEqual(model.phase, .saved(.created))
        XCTAssertEqual(model.systemPasswordOfferPhase, .failed)
        XCTAssertEqual(offerCount, 1)
        var savedDescriptors = try await store.savedCredentialDescriptors(in: work.id)
        XCTAssertEqual(savedDescriptors.count, 1)

        await model.offerToSystemPasswords {
            offerCount += 1
        }

        XCTAssertEqual(model.phase, .saved(.created))
        XCTAssertEqual(model.systemPasswordOfferPhase, .completed)
        XCTAssertEqual(offerCount, 2)
        savedDescriptors = try await store.savedCredentialDescriptors(in: work.id)
        XCTAssertEqual(savedDescriptors.count, 1)
    }

    func testContentBridgeRunsInsideASandboxedSubframeWithoutTreatingItAsMainFrame() async throws {
        let frameStatesExpectation = expectation(description: "main and sandboxed frame states")
        frameStatesExpectation.expectedFulfillmentCount = 2
        frameStatesExpectation.assertForOverFulfill = false
        var frameStates:
            [(
                isMainFrame: Bool,
                hasPassword: Bool,
                securityProtocol: String,
                securityHost: String
            )] = []

        _ = try await credentialBridgeWebView(
            html: """
                <!doctype html>
                <iframe sandbox="allow-forms allow-scripts" srcdoc="
                  <style>input { width: 220px; height: 32px; }</style>
                  <input type='password' autocomplete='current-password'>
                "></iframe>
                """
        ) { scriptMessage in
            guard let message = BrowserCredentialFormMessage(body: scriptMessage.body),
                message.event == .documentState,
                let hasPassword = message.hasVisiblePasswordField
            else { return }
            frameStates.append(
                (
                    scriptMessage.frameInfo.isMainFrame,
                    hasPassword,
                    scriptMessage.frameInfo.securityOrigin.protocol,
                    scriptMessage.frameInfo.securityOrigin.host
                ))
            if frameStates.count <= 2 {
                frameStatesExpectation.fulfill()
            }
        }

        await fulfillment(of: [frameStatesExpectation], timeout: 1)
        XCTAssertTrue(frameStates.contains { $0.isMainFrame && !$0.hasPassword })
        XCTAssertTrue(frameStates.contains { !$0.isMainFrame && $0.hasPassword })
        let sandboxedFrame = try XCTUnwrap(frameStates.first { !$0.isMainFrame })
        XCTAssertTrue(
            sandboxedFrame.securityProtocol.isEmpty
                || sandboxedFrame.securityHost.isEmpty
                || sandboxedFrame.securityProtocol == "about",
            "Expected an opaque sandbox origin, got \(sandboxedFrame.securityProtocol)://\(sandboxedFrame.securityHost)"
        )
    }

    func testIsolatedBridgeClassifiesAndFillsAnOrdinaryLoginForm() async throws {
        let webView = try await credentialBridgeWebView(
            html: """
                <!doctype html>
                <style>input { display: block; width: 220px; height: 32px; }</style>
                <form id="login">
                  <input id="login-user" autocomplete="username" value="person@example.com">
                  <input id="login-password" type="password" autocomplete="current-password" value="old-secret">
                </form>
                """)

        let inspectionResult = try await inspect("#login", in: webView)
        let inspection = try XCTUnwrap(inspectionResult)
        let pageWorldBridgeVisibility = try await webView.callAsyncJavaScript(
            "return typeof globalThis.__crestCredentialBridge;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        XCTAssertEqual(pageWorldBridgeVisibility as? String, "undefined")
        XCTAssertEqual(inspection["username"] as? String, "person@example.com")
        XCTAssertEqual(inspection["passwordKind"] as? String, "current")
        XCTAssertEqual(inspection["passwordFieldID"] as? String, "login-password")
        XCTAssertEqual(inspection["passwordFieldCount"] as? Int, 1)

        let formID = try XCTUnwrap(inspection["formID"] as? String)
        let didFill = try await fill(
            formID: formID,
            username: "filled@example.com",
            password: "filled-secret",
            in: webView
        )
        XCTAssertTrue(didFill)
        let pageValues = try await pageJSON(
            """
            return JSON.stringify({
              username: document.querySelector('#login-user').value,
              password: document.querySelector('#login-password').value
            });
            """,
            in: webView
        )
        XCTAssertEqual(pageValues["username"] as? String, "filled@example.com")
        XCTAssertEqual(pageValues["password"] as? String, "filled-secret")
    }

    func testIsolatedBridgeClassifiesAndFillsAnOpenShadowRootLogin() async throws {
        let webView = try await credentialBridgeWebView(
            html: """
                <!doctype html>
                <div id="shadow-host"></div>
                <script>
                  const root = document.querySelector('#shadow-host').attachShadow({ mode: 'open' });
                  root.innerHTML = `
                    <style>input { display: block; width: 220px; height: 32px; }</style>
                    <input id="shadow-user" autocomplete="username" value="shadow@example.com">
                    <input id="shadow-password" type="password" autocomplete="current-password" value="old-shadow-secret">
                  `;
                </script>
                """)

        let inspectionResult = try await inspect("#shadow-host", in: webView)
        let inspection = try XCTUnwrap(inspectionResult)
        XCTAssertEqual(inspection["username"] as? String, "shadow@example.com")
        XCTAssertEqual(inspection["passwordKind"] as? String, "current")
        XCTAssertEqual(inspection["passwordFieldID"] as? String, "shadow-password")

        let formID = try XCTUnwrap(inspection["formID"] as? String)
        let didFill = try await fill(
            formID: formID,
            username: "filled-shadow@example.com",
            password: "filled-shadow-secret",
            in: webView
        )
        XCTAssertTrue(didFill)
        let pageValues = try await pageJSON(
            """
            const root = document.querySelector('#shadow-host').shadowRoot;
            return JSON.stringify({
              username: root.querySelector('#shadow-user').value,
              password: root.querySelector('#shadow-password').value
            });
            """,
            in: webView
        )
        XCTAssertEqual(pageValues["username"] as? String, "filled-shadow@example.com")
        XCTAssertEqual(pageValues["password"] as? String, "filled-shadow-secret")
    }

    private func credentialBridgeWebView(
        html: String,
        receive: @escaping @MainActor (WKScriptMessage) -> Void = { _ in }
    ) async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        _ = BrowserCredentialContentBridge.install(
            in: configuration.userContentController,
            receive: receive
        )
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        let waiter = CredentialBridgeNavigationWaiter(webView: webView)
        try await waiter.load(
            simulatedRequest: URLRequest(url: URL(string: "https://forms.crest.test/")!),
            responseHTML: html
        )
        return webView
    }

    private func inspect(_ selector: String, in webView: WKWebView) async throws -> [String: Any]? {
        let value = try await webView.callAsyncJavaScript(
            "return JSON.stringify(globalThis.__crestCredentialBridge?.inspectForTesting(selector) ?? null);",
            arguments: ["selector": selector],
            in: nil,
            contentWorld: BrowserCredentialContentBridge.contentWorld
        )
        let json = try XCTUnwrap(value as? String)
        if json == "null" { return nil }
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func fill(
        formID: String,
        username: String,
        password: String,
        in webView: WKWebView
    ) async throws -> Bool {
        let value = try await webView.callAsyncJavaScript(
            "return globalThis.__crestCredentialBridge?.fill(formID, username, password) === true;",
            arguments: [
                "formID": formID,
                "username": username,
                "password": password,
            ],
            in: nil,
            contentWorld: BrowserCredentialContentBridge.contentWorld
        )
        return try XCTUnwrap(value as? Bool)
    }

    private func fillGenerated(
        formID: String,
        password: String,
        in webView: WKWebView
    ) async throws -> Bool {
        let value = try await webView.callAsyncJavaScript(
            "return globalThis.__crestCredentialBridge?.fillGenerated(formID, password) === true;",
            arguments: [
                "formID": formID,
                "password": password,
            ],
            in: nil,
            contentWorld: BrowserCredentialContentBridge.contentWorld
        )
        return try XCTUnwrap(value as? Bool)
    }

    private func captureForTesting(_ selector: String, in webView: WKWebView) async throws -> Bool {
        let value = try await webView.callAsyncJavaScript(
            "return globalThis.__crestCredentialBridge?.captureForTesting(selector) === true;",
            arguments: ["selector": selector],
            in: nil,
            contentWorld: BrowserCredentialContentBridge.contentWorld
        )
        return try XCTUnwrap(value as? Bool)
    }

    private func pageJSON(_ script: String, in webView: WKWebView) async throws -> [String: Any] {
        let value = try await webView.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        let json = try XCTUnwrap(value as? String)
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private enum TestSystemPasswordOfferError: Error {
    case rejected
}

@MainActor
private final class CredentialBridgeNavigationWaiter: NSObject, WKNavigationDelegate {
    private weak var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, any Error>?

    init(webView: WKWebView) {
        self.webView = webView
        super.init()
        webView.navigationDelegate = self
    }

    func load(simulatedRequest request: URLRequest, responseHTML: String) async throws {
        guard let webView else { throw CredentialBridgeNavigationWaiterError.releasedWebView }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadSimulatedRequest(request, responseHTML: responseHTML)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        continuation?.resume()
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: any Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: any Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

private enum CredentialBridgeNavigationWaiterError: Error {
    case releasedWebView
}
