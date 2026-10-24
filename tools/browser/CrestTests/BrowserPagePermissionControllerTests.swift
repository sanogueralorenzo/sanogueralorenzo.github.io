import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserPagePermissionControllerTests: XCTestCase {
    func testDownloadAndLocationDismissalAreTemporaryAndExplicitChoicesArePreserved() async throws {
        let controller = BrowserPagePermissionController()
        let origin = SiteOrigin(scheme: "https", host: "files.example", port: 443)
        for permission in [SitePermission.automaticDownloads, .location] {
            let unavailable = await controller.response(
                to: permission, origin: origin, topLevelOrigin: origin, spaceName: "Work")
            XCTAssertEqual(unavailable, .denyOnce)
            controller.setPresentationAvailable(true)
            for choice in [BrowserSitePermissionPromptResponse.grantPersistently, .denyPersistently] {
                let task = Task {
                    await controller.response(to: permission, origin: origin, topLevelOrigin: origin, spaceName: "Work")
                }
                controller.resolve(try await pendingRequest(in: controller), response: choice)
                let response = await task.value
                XCTAssertEqual(response, choice == .grantPersistently ? .grantPersistently : .denyPersistently)
            }
            let task = Task {
                await controller.response(to: permission, origin: origin, topLevelOrigin: origin, spaceName: "Work")
            }
            _ = try await pendingRequest(in: controller)
            controller.setPresentationAvailable(false)
            let dismissed = await task.value
            XCTAssertEqual(dismissed, .denyOnce)
        }
    }

    private func pendingRequest(in controller: BrowserPagePermissionController) async throws -> UUID {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while controller.current == nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        return try XCTUnwrap(controller.current?.id)
    }

    func testMediaRevocationStopsOnlyTheRevokedCapture() {
        let pages = RecordingEnginePages()
        let center = BrowserSitePermissionCenter()
        let spaceID = UUID()
        let origin = SiteOrigin(scheme: "https", host: "media.example", port: 443)
        center.setDecision(.grantPersistently, for: .camera, origin: origin, in: spaceID)
        center.setDecision(.grantPersistently, for: .microphone, origin: origin, in: spaceID)
        let session = BrowserPageSitePermissionSession(
            page: pages.page(), permissionCenter: center, spaceID: spaceID)
        session.recordMediaGrant(.camera, origin: origin)
        session.recordMediaGrant(.microphone, origin: origin)
        center.setDecision(.denyPersistently, for: .notifications, origin: origin, in: spaceID)
        center.setDecision(.ask, for: .camera, origin: origin, in: spaceID)
        XCTAssertEqual(pages.stopped, [.camera])
    }

    func testDecisionChangedElsewhereReachesAnEngineThatEnforcesItAtOnce() {
        let pages = RecordingEnginePages()
        let center = BrowserSitePermissionCenter()
        let spaceID = UUID()
        let page = URL(string: "https://maps.example/route")!
        let origin = SiteOrigin(scheme: "https", host: "maps.example", port: 443)
        let other = SiteOrigin(scheme: "https", host: "other.example", port: 443)
        let session = BrowserPageSitePermissionSession(page: pages.page(), permissionCenter: center, spaceID: spaceID)
        session.siteURL = { page }
        var refreshed: [SitePermission] = []
        session.siteDecisionDidChange = { refreshed.append($0) }

        center.setDecision(.grantPersistently, for: .location, origin: other, in: spaceID)
        center.setDecision(.grantPersistently, for: .location, origin: origin, in: UUID())
        XCTAssertTrue(pages.applied.isEmpty)

        center.setDecision(.denyPersistently, for: .location, origin: origin, in: spaceID)
        XCTAssertEqual(pages.applied.map(\.permission), [.location])
        XCTAssertEqual(pages.applied.map(\.allowed), [false])
        XCTAssertEqual(refreshed, [.location])
    }

    func testDismissalCancelsQueueWithoutSavingDenialsOrAnsweringLaterRequests() throws {
        let controller = BrowserPagePermissionController()
        controller.setPresentationAvailable(true)
        let origin = SiteOrigin(scheme: "https", host: "camera.example", port: 443)
        var responses: [BrowserSitePermissionPromptResponse?] = []
        for permission in [SitePermission.camera, .notifications] {
            controller.request(permission, origin: origin, topLevelOrigin: origin, spaceName: "Work") {
                responses.append($0)
            }
        }
        let staleID = try XCTUnwrap(controller.current?.id)
        controller.cancelAll()
        XCTAssertEqual(responses.count, 2)
        XCTAssertTrue(responses.allSatisfy { $0 == nil })
        controller.request(.camera, origin: origin, topLevelOrigin: origin, spaceName: "Work") {
            responses.append($0)
        }
        controller.resolve(staleID, response: .grantPersistently)
        XCTAssertEqual(responses.count, 2)
        controller.setPresentationAvailable(false)
        XCTAssertEqual(responses.count, 3)
        XCTAssertNil(responses.last!)
    }

    func testOriginsAndPermissionsRemainSeparateAndUnavailablePagesDenyTransiently() throws {
        let controller = BrowserPagePermissionController()
        let top = SiteOrigin(scheme: "https", host: "top.example", port: 443)
        let frame = SiteOrigin(scheme: "https", host: "frame.example", port: 443)
        var count = 0
        controller.request(.camera, origin: frame, topLevelOrigin: top, spaceName: "Work") {
            XCTAssertNil($0)
            count += 1
        }
        XCTAssertEqual(count, 1)
        XCTAssertNil(controller.current)
        controller.setPresentationAvailable(true)
        controller.request(.camera, origin: frame, topLevelOrigin: top, spaceName: "Work") { _ in }
        controller.request(.camera, origin: top, topLevelOrigin: top, spaceName: "Work") { _ in }
        let first = try XCTUnwrap(controller.current)
        XCTAssertEqual(first.origin, frame)
        controller.resolve(first.id, response: .denyPersistently)
        XCTAssertEqual(controller.current?.origin, top)
        controller.cancelAll()
    }
}

/// An engine's direct path that records the site decisions carried to it.
@MainActor
private final class RecordingEnginePages: EnginePages {
    private(set) var applied: [(permission: SitePermission, allowed: Bool?)] = []
    private(set) var stopped: [SitePermission] = []

    /// A page over this path.
    func page() -> EnginePage {
        EnginePage(id: UUID(), pages: self, historyFamily: .chromium, historyVersion: { nil }, inspectorPanels: [])
    }

    func attach(_ page: EnginePage) {}

    func request<Request: PageRequest>(_ request: Request) -> Request.Answer {
        switch request {
        case let setting as SetSitePermission: applied.append((setting.permission, setting.allowed))
        case let stopping as StopMediaCapture: stopped.append(stopping.permission)
        default: XCTFail("The session asked for \(Request.self).")
        }
        guard let answer = true as? Request.Answer else { preconditionFailure("A site request answers Bool.") }
        return answer
    }
}
