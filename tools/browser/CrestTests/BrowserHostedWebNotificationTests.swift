import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserHostedWebNotificationTests: XCTestCase {
    func testLivePageBridgeReportsPermissionDeliversAndReceivesClicks() async throws {
        let originURL = try XCTUnwrap(URL(string: "https://notifications.crest.test/"))
        let origin = try XCTUnwrap(SiteOrigin(url: originURL))
        let tab = TabState.Seed(
            title: "Notifications",
            url: nil,
            placement: .current
        )
        let space = SpaceState.Seed(
            name: "Work",
            symbol: "briefcase",
            accent: .teal,
            folders: [],
            tabs: [tab],
            browsingPreferences: BrowsingPreferences.seeded(cleanup: .never, blocking: .off)
        )
        let permissionCenter = BrowserSitePermissionCenter()
        permissionCenter.setDecision(
            .grantPersistently,
            for: .notifications,
            origin: origin,
            in: space.id
        )
        let systemCenter = TestHostedWebNotificationCenter(
            authorization: .authorized
        )
        let pool = BrowserPagePool(
            browser: .hostingPages(SessionState.Seed(spaces: [space])),
            usesEphemeralWebsiteDataStores: true,
            permissionCenter: permissionCenter,
            hostedNotificationCenter: systemCenter
        )

        pool.present(tab: tab.id, in: space.id)
        let page = try XCTUnwrap(pool.activePage)
        page.webView.loadSimulatedRequest(
            URLRequest(url: originURL),
            responseHTML: "<!doctype html><title>Notification fixture</title>"
        )
        try await waitUntil("the notification bridge to synchronize permission") {
            try await self.stringResult(
                from: page.webView,
                script: "return Notification.permission;"
            ) == "granted"
        }

        _ = try await page.webView.callAsyncJavaScript(
            """
            globalThis.crestNotificationClicked = false;
            globalThis.crestNotificationShown = false;
            const notification = new Notification(title, { body });
            notification.onclick = () => { globalThis.crestNotificationClicked = true; };
            notification.onshow = () => { globalThis.crestNotificationShown = true; };
            globalThis.crestNotification = notification;
            """,
            arguments: ["title": "Build complete", "body": "Everything passed."],
            in: nil,
            contentWorld: .page
        )

        try await waitUntil("the native notification delivery") {
            systemCenter.deliveries.count == 1
        }
        let delivery = try XCTUnwrap(systemCenter.deliveries.first)
        XCTAssertEqual(delivery.title, "Build complete")
        XCTAssertEqual(delivery.body, "Everything passed.")
        XCTAssertEqual(delivery.origin, origin)
        XCTAssertFalse(delivery.isSilent)

        systemCenter.simulateClick(identifier: delivery.identifier)
        try await waitUntil("the page notification click event") {
            try await self.boolResult(
                from: page.webView,
                script: "return globalThis.crestNotificationClicked === true;"
            )
        }

        _ = try await page.webView.callAsyncJavaScript(
            "globalThis.crestNotification.close();",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        try await waitUntil("the native notification withdrawal") {
            systemCenter.removedIdentifiers.contains(delivery.identifier)
        }

        systemCenter.pausesAdds = true
        _ = try await page.webView.callAsyncJavaScript(
            "new Notification('Stale delivery');",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        try await waitUntil("the stale delivery to enter the native center") {
            systemCenter.attemptedDeliveries.count == 2
        }
        let staleDelivery = try XCTUnwrap(systemCenter.attemptedDeliveries.last)
        page.beginHostedWebNotificationNavigation()
        systemCenter.resumeAdds()
        try await waitUntil("the stale delivery to be withdrawn") {
            systemCenter.removedIdentifiers.contains(staleDelivery.identifier)
        }
        XCTAssertFalse(
            systemCenter.deliveries.contains(where: {
                $0.identifier == staleDelivery.identifier
            })
        )

        pool.reconcile(validTabIDs: [])
    }

    private func stringResult(
        from webView: WKWebView,
        script: String
    ) async throws -> String {
        let result = try await webView.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        return try XCTUnwrap(result as? String)
    }

    private func boolResult(
        from webView: WKWebView,
        script: String
    ) async throws -> Bool {
        let result = try await webView.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        return try XCTUnwrap(result as? Bool)
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
private final class TestHostedWebNotificationCenter:
    BrowserHostedWebNotificationCentering
{
    private struct Registration {
        let delivery: BrowserHostedWebNotificationDelivery
        let eventHandler: @MainActor (BrowserHostedWebNotificationEvent) -> Void
    }

    var authorization: BrowserSystemAuthorization
    private var registrations: [String: Registration] = [:]
    private var addContinuations: [CheckedContinuation<Void, Never>] = []
    var pausesAdds = false
    private(set) var attemptedDeliveries: [BrowserHostedWebNotificationDelivery] = []
    private(set) var removedIdentifiers: Set<String> = []

    var deliveries: [BrowserHostedWebNotificationDelivery] {
        registrations.values.map(\.delivery)
    }

    init(authorization: BrowserSystemAuthorization) {
        self.authorization = authorization
    }

    func currentAuthorization() async -> BrowserSystemAuthorization {
        authorization
    }

    func requestAuthorization() async -> BrowserSystemAuthorization {
        return authorization
    }

    func add(
        _ delivery: BrowserHostedWebNotificationDelivery,
        eventHandler: @escaping @MainActor (BrowserHostedWebNotificationEvent) -> Void
    ) async throws {
        attemptedDeliveries.append(delivery)
        if pausesAdds {
            await withCheckedContinuation { continuation in
                addContinuations.append(continuation)
            }
        }
        registrations[delivery.identifier] = Registration(
            delivery: delivery,
            eventHandler: eventHandler
        )
    }

    func remove(identifier: String) async {
        registrations.removeValue(forKey: identifier)
        removedIdentifiers.insert(identifier)
    }

    func simulateClick(identifier: String) {
        registrations[identifier]?.eventHandler(.clicked)
    }

    func resumeAdds() {
        pausesAdds = false
        let continuations = addContinuations
        addContinuations.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }
}
