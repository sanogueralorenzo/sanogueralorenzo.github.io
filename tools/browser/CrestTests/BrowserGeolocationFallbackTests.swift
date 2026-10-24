import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserGeolocationBridgeTests: XCTestCase {
    func testDismissingLocationPromptKeepsAskAndRememberedAllowSkipsTheNextPrompt() async throws {
        let fixture = try makeFixture()
        defer { fixture.page.release(keepingState: false) }
        let origin = try XCTUnwrap(SiteOrigin(url: fixture.url))
        fixture.page.permissionCenter.setDecision(.ask, for: .location, origin: origin, in: fixture.page.spaceID)
        fixture.page.sitePermissionRequests.setPresentationAvailable(true)
        fixture.page.webView.loadSimulatedRequest(URLRequest(url: fixture.url), responseHTML: "<title>Location</title>")
        try await waitUntil("the loaded location document") {
            guard fixture.page.webView.url == fixture.url, !fixture.page.webView.isLoading else { return false }
            return try await fixture.page.webView.evaluateJavaScript("Boolean(globalThis.__crestGeolocationBridge)")
                as? Bool == true
        }
        try await waitUntil("the location bridge") {
            try await self.permissionState(in: fixture.page.webView) == "prompt"
        }
        func requestPosition() async throws {
            _ = try await fixture.page.webView.evaluateJavaScript(
                "globalThis.locationError = null; navigator.geolocation.getCurrentPosition(() => {}, e => { globalThis.locationError = e.code; });"
            )
        }
        try await requestPosition()
        try await waitUntil("the site location prompt") { fixture.page.sitePermissionRequests.current != nil }
        XCTAssertEqual(fixture.page.sitePermissionRequests.current?.permission, .location)
        fixture.page.sitePermissionRequests.cancelAll()
        try await waitUntil("the dismissed request callback") {
            try await self.doubleResult(in: fixture.page.webView, script: "return globalThis.locationError;") == 1
        }
        XCTAssertEqual(
            fixture.page.permissionCenter.decision(for: .location, origin: origin, in: fixture.page.spaceID), .ask)
        XCTAssertTrue(fixture.service.currentRequests.isEmpty)
        try await requestPosition()
        try await waitUntil("a new location request") { fixture.page.sitePermissionRequests.current != nil }
        fixture.page.sitePermissionRequests.resolve(
            try XCTUnwrap(fixture.page.sitePermissionRequests.current?.id), response: .grantPersistently)
        try await waitUntil("the authorized location request") { fixture.service.currentRequests.count == 1 }
        try await requestPosition()
        try await waitUntil("the next request without another prompt") { fixture.service.currentRequests.count == 2 }
        XCTAssertNil(fixture.page.sitePermissionRequests.current)
    }

    func testRevocationStopsRequestsAndRejectsLateCallbacksAfterRegrant() async throws {
        for action in Revocation.allCases {
            let fixture = try makeFixture()
            defer { fixture.page.release(keepingState: false) }
            let origin = try XCTUnwrap(SiteOrigin(url: fixture.url))
            try await loadRequests(in: fixture)
            let current = try XCTUnwrap(fixture.service.currentRequests.first?.value)
            let watch = try XCTUnwrap(fixture.service.watchRequests.first?.value)
            switch action {
            case .block, .ask:
                fixture.page.permissionCenter.setDecision(
                    action == .block ? .denyPersistently : .ask,
                    for: .location, origin: origin, in: fixture.page.spaceID
                )
            case .originReset:
                fixture.page.permissionCenter.reset(
                    recordID: try XCTUnwrap(
                        fixture.page.permissionCenter.records(in: fixture.page.spaceID).first?.id
                    ))
            case .spaceReset:
                fixture.page.permissionCenter.reset(spaceID: fixture.page.spaceID)
            }
            XCTAssertTrue(
                fixture.service.currentRequests.isEmpty, "\(action) cancels in-flight positions synchronously")
            XCTAssertTrue(fixture.service.watchRequests.isEmpty, "\(action) stops the native watch synchronously")
            fixture.page.permissionCenter.setDecision(
                .grantPersistently, for: .location, origin: origin, in: fixture.page.spaceID
            )
            current.receive(.success(Self.position))
            watch.receive(.success(Self.position))
            try await expectCounts(in: fixture, successes: 0, denials: 2)
            _ = try await fixture.page.webView.evaluateJavaScript(
                "navigator.geolocation.getCurrentPosition(success, failure);"
            )
            try await waitUntil("a fresh request after regrant") { fixture.service.currentRequests.count == 1 }
            try XCTUnwrap(fixture.service.currentRequests.first?.value).receive(.success(Self.position))
            try await expectCounts(in: fixture, successes: 1, denials: 2)
        }
    }

    func testAllowOnceSurvivesOrdinaryUseButAskAgainRevokesItAndFreshRequestsAsk() async throws {
        let fixture = try makeFixture()
        defer { fixture.page.release(keepingState: false) }
        let origin = try XCTUnwrap(SiteOrigin(url: fixture.url))
        fixture.page.permissionCenter.setDecision(.ask, for: .location, origin: origin, in: fixture.page.spaceID)
        fixture.page.sitePermissionRequests.setPresentationAvailable(true)
        try await loadRequests(in: fixture, startsAuthorized: false, watchOnly: true)
        try await resolvePrompt(in: fixture, response: .allowOnce)
        try await waitUntil("the once-authorized watch") { fixture.service.watchRequests.count == 1 }
        let watch = try XCTUnwrap(fixture.service.watchRequests.first?.value)
        watch.receive(.success(Self.position))
        try await expectCounts(in: fixture, successes: 1, denials: 0)
        let state = try await permissionState(in: fixture.page.webView)
        XCTAssertEqual(state, "prompt", "Allow Once must not create a stored grant")
        fixture.page.permissionCenter.setDecision(.ask, for: .location, origin: origin, in: fixture.page.spaceID)
        XCTAssertTrue(fixture.service.watchRequests.isEmpty)
        watch.receive(.success(Self.position))
        try await expectCounts(in: fixture, successes: 1, denials: 1)
        _ = try await fixture.page.webView.evaluateJavaScript(
            "navigator.geolocation.getCurrentPosition(success, failure);"
        )
        try await resolvePrompt(in: fixture, response: .denyOnce)
        try await expectCounts(in: fixture, successes: 1, denials: 2)
        fixture.page.permissionCenter.setDecision(
            .denyPersistently, for: .location, origin: origin, in: fixture.page.spaceID)
        _ = try await fixture.page.webView.evaluateJavaScript(
            "navigator.geolocation.getCurrentPosition(success, failure);"
        )
        try await expectCounts(in: fixture, successes: 1, denials: 3)
        XCTAssertNil(fixture.page.sitePermissionRequests.current)
        XCTAssertTrue(fixture.service.currentRequests.isEmpty)
    }

    func testRevocationDuringSiteOrSystemConsentCannotPersistOrStartOldRequest() async throws {
        for awaitsSystem in [false, true] {
            let fixture = try makeFixture(systemAuthorization: awaitsSystem ? .notDetermined : .authorized)
            defer { fixture.page.release(keepingState: false) }
            let origin = try XCTUnwrap(SiteOrigin(url: fixture.url))
            fixture.page.permissionCenter.setDecision(.ask, for: .location, origin: origin, in: fixture.page.spaceID)
            fixture.page.sitePermissionRequests.setPresentationAvailable(true)
            fixture.service.delaysAuthorization = awaitsSystem
            try await loadRequests(in: fixture, startsAuthorized: false, watchOnly: true)
            try await waitUntil("the site consent request") { fixture.page.sitePermissionRequests.current != nil }
            let promptID = try XCTUnwrap(fixture.page.sitePermissionRequests.current?.id)
            if awaitsSystem {
                fixture.page.sitePermissionRequests.resolve(promptID, response: .grantPersistently)
                try await waitUntil("the OS consent request") { fixture.service.authorizationContinuation != nil }
            }
            fixture.page.permissionCenter.reset(spaceID: fixture.page.spaceID)
            try await expectCounts(in: fixture, successes: 0, denials: 1)
            if awaitsSystem {
                fixture.service.authorization = .authorized
                fixture.service.authorizationContinuation?.resume(returning: .authorized)
                fixture.service.authorizationContinuation = nil
            } else {
                fixture.page.sitePermissionRequests.resolve(promptID, response: .grantPersistently)
            }
            // Drain the resumed authorization task before examining its effects.
            _ = try await permissionState(in: fixture.page.webView)
            XCTAssertTrue(fixture.service.watchRequests.isEmpty)
            XCTAssertEqual(
                fixture.page.permissionCenter.decision(for: .location, origin: origin, in: fixture.page.spaceID), .ask)
            _ = try await fixture.page.webView.evaluateJavaScript(
                "navigator.geolocation.watchPosition(success, failure);")
            try await resolvePrompt(in: fixture, response: .allowOnce)
            try await waitUntil("fresh consent after withdrawal") { fixture.service.watchRequests.count == 1 }
            try XCTUnwrap(fixture.service.watchRequests.first?.value).receive(.success(Self.position))
            try await expectCounts(in: fixture, successes: 1, denials: 1)
        }
    }

    func testAnAllowTheSystemRefusesIsNotSaved() async throws {
        let fixture = try makeFixture(systemAuthorization: .notDetermined)
        defer { fixture.page.release(keepingState: false) }
        let origin = try XCTUnwrap(SiteOrigin(url: fixture.url))
        fixture.page.permissionCenter.setDecision(.ask, for: .location, origin: origin, in: fixture.page.spaceID)
        fixture.page.sitePermissionRequests.setPresentationAvailable(true)
        fixture.service.delaysAuthorization = true
        try await loadRequests(in: fixture, startsAuthorized: false, watchOnly: true)
        try await resolvePrompt(in: fixture, response: .grantPersistently)
        try await waitUntil("the system's consent request") { fixture.service.authorizationContinuation != nil }
        // The person's Allow waits on the system before the core hears it.
        XCTAssertEqual(
            fixture.page.permissionCenter.decision(for: .location, origin: origin, in: fixture.page.spaceID), .ask)
        fixture.service.authorization = .denied
        fixture.service.authorizationContinuation?.resume(returning: .denied)
        fixture.service.authorizationContinuation = nil
        try await expectCounts(in: fixture, successes: 0, denials: 1)
        XCTAssertEqual(
            fixture.page.permissionCenter.decision(for: .location, origin: origin, in: fixture.page.spaceID), .ask)
        XCTAssertTrue(fixture.service.watchRequests.isEmpty)
    }

    func testQueuedDeliveryRechecksSiteAndSystemAuthorization() async throws {
        for revokesSystem in [false, true] {
            let fixture = try makeFixture()
            defer { fixture.page.release(keepingState: false) }
            try await loadRequests(in: fixture)
            let current = try XCTUnwrap(fixture.service.currentRequests.first?.value)
            let watch = try XCTUnwrap(fixture.service.watchRequests.first?.value)
            current.receive(.success(Self.position))
            watch.receive(.success(Self.position))
            // Revoke before the asynchronous WebKit delivery tasks get a turn.
            if revokesSystem {
                fixture.service.authorization = .denied
            } else {
                fixture.page.permissionCenter.reset(spaceID: fixture.page.spaceID)
            }
            try await expectCounts(in: fixture, successes: 0, denials: 2)
            XCTAssertTrue(fixture.service.currentRequests.isEmpty)
            XCTAssertTrue(fixture.service.watchRequests.isEmpty)
        }
    }

    private enum Revocation: CaseIterable { case block, ask, originReset, spaceReset }
    /// The page, and the window that opened it through the core, which lives as
    /// long as the page.
    private typealias Fixture = (
        page: BrowserPage, service: TestBrowserGeolocationService, url: URL, browser: BrowserStore
    )

    private func loadRequests(in fixture: Fixture, startsAuthorized: Bool = true, watchOnly: Bool = false) async throws
    {
        fixture.page.webView.loadSimulatedRequest(URLRequest(url: fixture.url), responseHTML: "<title>Location</title>")
        try await waitUntil("the location document") {
            guard fixture.page.webView.url == fixture.url, !fixture.page.webView.isLoading else { return false }
            return try await self.permissionState(in: fixture.page.webView) == (startsAuthorized ? "granted" : "prompt")
        }
        _ = try await fixture.page.webView.evaluateJavaScript(
            """
            globalThis.successes = 0; globalThis.denials = 0;
            globalThis.success = () => { globalThis.successes++; };
            globalThis.failure = e => { if (e.code === 1) globalThis.denials++; };
            globalThis.watchID = navigator.geolocation.watchPosition(success, failure);
            """)
        if !watchOnly {
            _ = try await fixture.page.webView.evaluateJavaScript(
                "navigator.geolocation.getCurrentPosition(success, failure);")
        }
        if startsAuthorized {
            try await waitUntil("the native requests") {
                fixture.service.watchRequests.count == 1 && (watchOnly || fixture.service.currentRequests.count == 1)
            }
        }
    }

    private func expectCounts(in fixture: Fixture, successes: Double, denials: Double) async throws {
        try await waitUntil("\(denials) permission denials and \(successes) successes") {
            let counts =
                try await fixture.page.webView.evaluateJavaScript("[globalThis.successes, globalThis.denials]")
                as? [Double]
            return counts == [successes, denials]
        }
    }

    private func resolvePrompt(in fixture: Fixture, response: BrowserSitePermissionPromptResponse) async throws {
        try await waitUntil("a fresh site consent prompt") { fixture.page.sitePermissionRequests.current != nil }
        fixture.page.sitePermissionRequests.resolve(
            try XCTUnwrap(fixture.page.sitePermissionRequests.current?.id), response: response)
    }

    private static let position = BrowserGeolocationPosition(
        latitude: 41.8781,
        longitude: -87.6298,
        accuracy: 12,
        altitude: nil,
        altitudeAccuracy: nil,
        heading: nil,
        speed: nil,
        timestamp: 1_786_944_000_000
    )

    private func makeFixture(
        systemAuthorization: BrowserSystemAuthorization = .authorized,
        recoversSystemAuthorization: Bool = false,
        url: URL? = nil,
        space: SpaceState.Seed? = nil
    ) throws -> Fixture {
        let url = try XCTUnwrap(url ?? URL(string: "https://location.crest.test/"))
        let origin = try XCTUnwrap(SiteOrigin(url: url))
        let space = try XCTUnwrap(space ?? SessionState.Seed.preview.spaces.first)
        let browser = BrowserStore.hostingPages(SessionState.Seed(spaces: [space]))
        // The Space's choices live in the core that hosts the page, as in the app.
        let permissionCenter = BrowserSitePermissionCenter(core: browser.core)
        permissionCenter.setDecision(
            .grantPersistently,
            for: .location,
            origin: origin,
            in: space.id
        )
        let service = TestBrowserGeolocationService(
            authorization: systemAuthorization
        )
        let page = try XCTUnwrap(
            browser.openWebKitPage(in: space.id, for: nil).map {
                opened in
                BrowserPage(
                    corePage: opened.core,
                    webKitPage: opened.webKit,
                    dialogPresenter: BrowserDialogPresenter(),
                    downloadCenter: BrowserDownloadCenter(),
                    permissionCenter: permissionCenter,
                    geolocationService: service,
                    recoverGeolocationSystemAuthorization: {
                        service.recoveryCount += 1
                        if recoversSystemAuthorization {
                            service.authorization = .authorized
                        }
                    },
                    spaceID: space.id,
                    profileID: space.profileID,
                    spaceName: space.settings.name,
                    openNewTab: { _ in }
                )
            })
        return (page, service, url, browser)
    }

    private func permissionState(in webView: WKWebView) async throws -> String? {
        try await webView.callAsyncJavaScript(
            "return (await navigator.permissions.query({ name: 'geolocation' })).state;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? String
    }

    private func doubleResult(in webView: WKWebView, script: String) async throws -> Double? {
        try await webView.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? Double
    }

    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(5),
        condition: () async throws -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for \(description).")
    }
}

@MainActor
private final class TestBrowserGeolocationService: BrowserGeolocationServicing {
    struct Request {
        let options: BrowserGeolocationRequestOptions
        let receive: @MainActor (Result<BrowserGeolocationPosition, BrowserGeolocationError>) -> Void
    }

    var currentRequests: [String: Request] = [:]
    var watchRequests: [String: Request] = [:]
    var cancelledIdentifiers: Set<String> = []
    var authorization: BrowserSystemAuthorization
    var recoveryCount = 0
    var delaysAuthorization = false
    var authorizationContinuation: CheckedContinuation<BrowserSystemAuthorization, Never>?

    init(authorization: BrowserSystemAuthorization) {
        self.authorization = authorization
    }

    func currentAuthorization() -> BrowserSystemAuthorization {
        authorization
    }

    func requestAuthorization() async -> BrowserSystemAuthorization {
        if delaysAuthorization {
            return await withCheckedContinuation { authorizationContinuation = $0 }
        }
        return authorization
    }

    func requestCurrentPosition(
        identifier: String,
        options: BrowserGeolocationRequestOptions,
        receive: @escaping @MainActor (Result<BrowserGeolocationPosition, BrowserGeolocationError>) -> Void
    ) {
        currentRequests[identifier] = Request(options: options, receive: receive)
    }

    func startWatchingPosition(
        identifier: String,
        options: BrowserGeolocationRequestOptions,
        receive: @escaping @MainActor (Result<BrowserGeolocationPosition, BrowserGeolocationError>) -> Void
    ) {
        watchRequests[identifier] = Request(options: options, receive: receive)
    }

    func cancel(identifier: String) {
        currentRequests.removeValue(forKey: identifier)
        watchRequests.removeValue(forKey: identifier)
        cancelledIdentifiers.insert(identifier)
    }

    func cancelAll() {
        currentRequests.removeAll()
        watchRequests.removeAll()
    }
}
