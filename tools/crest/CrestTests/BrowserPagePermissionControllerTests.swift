import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserPagePermissionControllerTests: XCTestCase {
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
