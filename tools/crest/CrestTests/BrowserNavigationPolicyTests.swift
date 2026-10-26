import Foundation
import WebKit
import XCTest

@testable import Crest

final class BrowserNavigationPolicyTests: XCTestCase {
    func testExternalSchemeNavigationIntentOutranksDownloadsAndNewTabs() throws {
        let mailURL = try XCTUnwrap(URL(string: "mailto:person@example.com"))

        XCTAssertEqual(
            BrowserNavigationDecision.classify(
                url: mailURL,
                hasTargetFrame: false,
                shouldPerformDownload: true
            ),
            .handOffToSystem(mailURL)
        )
        XCTAssertEqual(
            BrowserNavigationDecision.classify(
                url: try XCTUnwrap(URL(string: "javascript:alert(1)")),
                hasTargetFrame: true,
                shouldPerformDownload: false
            ),
            .blockScheme
        )
        XCTAssertEqual(
            BrowserNavigationDecision.classify(
                url: try XCTUnwrap(URL(string: "https://example.com/next")),
                hasTargetFrame: true,
                shouldPerformDownload: false
            ),
            .allow
        )
    }
}

@MainActor
final class BrowserExternalSchemeCoordinatorTests: XCTestCase {
    func testUserInitiatedHandOffPromptsOnceThenRemembersTheApproval() async throws {
        let harness = Harness(response: .openAndRemember)
        let mailURL = try XCTUnwrap(URL(string: "mailto:person@example.com"))

        await harness.coordinator.resolve(
            destinationURL: mailURL,
            trigger: .explicitUserNavigation,
            origin: harness.origin
        )

        XCTAssertEqual(harness.opened, [mailURL])
        XCTAssertEqual(harness.promptCount, 1)
        XCTAssertEqual(
            harness.permissionCenter.decision(
                for: .externalApplications,
                origin: harness.origin,
                detail: "mailto",
                in: harness.spaceID
            ),
            .grantPersistently
        )

        await harness.coordinator.resolve(
            destinationURL: mailURL,
            trigger: .explicitUserNavigation,
            origin: harness.origin
        )

        XCTAssertEqual(harness.opened, [mailURL, mailURL])
        XCTAssertEqual(harness.promptCount, 1, "A remembered approval must skip the prompt.")
    }

    func testScriptedHandOffOpensWhenTheOriginAlreadyApprovedThatScheme() async throws {
        let harness = Harness(response: .cancel)
        let meetingURL = try XCTUnwrap(URL(string: "zoommtg://zoom.us/join?confno=1"))
        let mailURL = try XCTUnwrap(URL(string: "mailto:person@example.com"))
        harness.permissionCenter.setDecision(
            .grantPersistently,
            for: .externalApplications,
            origin: harness.origin,
            detail: "zoommtg",
            in: harness.spaceID
        )

        await harness.coordinator.resolve(
            destinationURL: meetingURL,
            trigger: .scripted,
            origin: harness.origin
        )
        await harness.coordinator.resolve(
            destinationURL: mailURL,
            trigger: .scripted,
            origin: harness.origin
        )

        XCTAssertEqual(
            harness.opened,
            [meetingURL],
            "Approving one scheme must not approve every other scheme."
        )
        XCTAssertEqual(
            harness.promptCount,
            1,
            "An unapproved scheme from the same origin must still ask."
        )
    }

    @MainActor
    private final class Harness {
        let spaceID = UUID()
        let origin = SiteOrigin(scheme: "https", host: "mail.example", port: 443)
        let permissionCenter = BrowserSitePermissionCenter()
        let coordinator: BrowserExternalSchemeCoordinator
        private(set) var opened: [URL] = []
        private(set) var promptCount = 0

        init(response: BrowserExternalSchemePromptResponse) {
            var recordOpen: (URL) -> Void = { _ in }
            var recordPrompt: () -> Void = {}
            coordinator = BrowserExternalSchemeCoordinator(
                spaceID: spaceID,
                spaceName: "Work",
                permissionCenter: permissionCenter,
                prompt: { _, _, _ in
                    recordPrompt()
                    return response
                },
                opensExternalURL: { recordOpen($0) }
            )
            recordOpen = { [weak self] url in self?.opened.append(url) }
            recordPrompt = { [weak self] in self?.promptCount += 1 }
        }
    }
}

@MainActor
final class BrowserDownloadNavigationLifecycleTests: XCTestCase {
}

@MainActor
final class BrowserPopupSchemeRoutingTests: XCTestCase {

    func testABlockedSchemePopupIsDroppedWithoutAHandOffOrAPage() throws {
        for address in ["javascript:alert(1)", "file:///etc/passwd"] {
            let harness = Harness()

            let webView = harness.resolveOpen(
                url: try XCTUnwrap(URL(string: address)),
                navigationType: .linkActivated,
                currentURL: try XCTUnwrap(URL(string: "https://hostile.example/"))
            )

            XCTAssertNil(webView)
            XCTAssertTrue(harness.handedOff.isEmpty, "\(address) must not launch another app.")
            XCTAssertTrue(harness.offeredURLs.isEmpty)
        }
    }

    @MainActor
    private final class Harness {
        struct HandOff: Equatable {
            let url: URL
            let trigger: BrowserPopupTrigger
            let origin: SiteOrigin?
        }

        let coordinator: BrowserPopupCoordinator
        private(set) var handedOff: [HandOff] = []
        private(set) var offeredURLs: [URL?] = []

        init() {
            var recordHandOff: (HandOff) -> Void = { _ in }
            coordinator = BrowserPopupCoordinator(
                handOffExternalScheme: { url, trigger, origin in
                    recordHandOff(HandOff(url: url, trigger: trigger, origin: origin))
                }
            )
            recordHandOff = { [weak self] handOff in self?.handedOff.append(handOff) }
        }

        func resolveOpen(
            url: URL?,
            navigationType: WKNavigationType,
            currentURL: URL?
        ) -> WKWebView? {
            coordinator.resolveOpen(
                for: StubNewWindowNavigationAction(
                    url: url,
                    navigationType: navigationType
                ),
                currentURL: currentURL
            ) { requestedURL in
                self.offeredURLs.append(requestedURL)
                return nil
            }
        }
    }
}

/// WebKit never lets an app build a real `WKNavigationAction`, so this stands in
/// for the one handed to `createWebViewWith`: no target frame, and a navigation
/// type that selects the popup trigger under test. It deliberately has no source
/// frame, which is how the coordinator's fallback to the visible page is covered.
private final class StubNewWindowNavigationAction: WKNavigationAction,
    BrowserNavigationActionSourceOriginProviding
{
    private let stubRequest: URLRequest
    private let stubNavigationType: WKNavigationType

    init(url: URL?, navigationType: WKNavigationType) {
        var request = URLRequest(url: URL(fileURLWithPath: "/"))
        request.url = url
        stubRequest = request
        stubNavigationType = navigationType
        super.init()
    }

    override var request: URLRequest { stubRequest }
    override var navigationType: WKNavigationType { stubNavigationType }
    override var targetFrame: WKFrameInfo? { nil }
    var browserSourceOrigin: SiteOrigin? { nil }
}
