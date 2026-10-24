import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserPageSystemConsentTests: XCTestCase {
    /// For each capability the system gates, a remembered Allow reaches the
    /// core only once the system consents; one the system refuses saves
    /// nothing and the site hears a denial.
    func testARememberedAllowIsSavedOnlyOnceTheSystemConsents() async throws {
        let origin = SiteOrigin(scheme: "https", host: "consent.crest.test", port: 443)
        for permission in [SitePermission.camera, .microphone, .cameraAndMicrophone, .notifications] {
            for systemConsents in [false, true] {
                let fixture = try makeFixture()
                defer { fixture.page.release(keepingState: false) }
                let consent = RecordingSystemConsent(consents: systemConsents)
                fixture.page.systemConsent = consent
                fixture.page.sitePermissionRequests.setPresentationAvailable(true)
                let asking = Task {
                    await fixture.webKitPage.ask(
                        PermissionQuestion(permission: permission, origin: origin, topLevelOrigin: origin))
                }
                try await waitUntil("the \(permission.name) prompt") {
                    fixture.page.sitePermissionRequests.current != nil
                }
                fixture.page.sitePermissionRequests.resolve(
                    try XCTUnwrap(fixture.page.sitePermissionRequests.current?.id), response: .grantPersistently)
                let granted = await asking.value
                let center = fixture.page.permissionCenter
                let saved =
                    permission.isMedia
                    ? center.mediaDecision(for: permission, origin: origin, in: fixture.page.spaceID)
                    : center.decision(for: permission, origin: origin, in: fixture.page.spaceID)
                XCTAssertEqual(consent.asked, [permission], permission.name)
                XCTAssertEqual(granted, systemConsents, permission.name)
                XCTAssertEqual(saved, systemConsents ? .grantPersistently : .ask, permission.name)
            }
        }
    }

    // MARK: - Fixtures

    /// The page, the WebKit page it hosts, and the window that opened it
    /// through the core, which lives as long as the page.
    private typealias Fixture = (page: BrowserPage, webKitPage: WebKitEnginePage, browser: BrowserStore)

    private func makeFixture() throws -> Fixture {
        let space = try XCTUnwrap(SessionState.Seed.preview.spaces.first)
        let browser = BrowserStore.hostingPages(SessionState.Seed(spaces: [space]))
        let opened = try XCTUnwrap(
            browser.openWebKitPage(in: space.id, for: nil))
        let page = BrowserPage(
            corePage: opened.core,
            webKitPage: opened.webKit,
            dialogPresenter: BrowserDialogPresenter(),
            downloadCenter: BrowserDownloadCenter(),
            // The Space's choices live in the core that hosts the page, as in the app.
            permissionCenter: BrowserSitePermissionCenter(core: browser.core),
            spaceID: space.id,
            profileID: space.profileID,
            spaceName: space.settings.name,
            openNewTab: { _ in }
        )
        return (page, opened.webKit, browser)
    }

    private func waitUntil(_ description: String, condition: () throws -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if try condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for \(description).")
    }
}

/// A system that answers every question the same way, and remembers what it
/// was asked.
@MainActor
private final class RecordingSystemConsent: BrowserSystemConsenting {
    private let answer: Bool
    private(set) var asked: [SitePermission] = []

    init(consents answer: Bool) {
        self.answer = answer
    }

    func consents(to permission: SitePermission) async -> Bool {
        asked.append(permission)
        return answer
    }
}
