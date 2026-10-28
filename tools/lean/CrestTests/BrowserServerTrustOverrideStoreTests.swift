import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserServerTrustOverrideStoreTests: XCTestCase {
    func testApprovalRequiresTheExactSpaceProfileHostPortAndCertificate() {
        let store = BrowserServerTrustOverrideStore()
        let profileID = UUID()
        let identity = BrowserServerTrustIdentity(
            host: "unsafe.example.test",
            port: 443,
            certificateSHA256: "AA11"
        )

        store.approve(identity, for: profileID)

        XCTAssertTrue(store.isApproved(identity, for: profileID))
        XCTAssertFalse(store.isApproved(identity, for: UUID()))
        XCTAssertFalse(
            store.isApproved(
                BrowserServerTrustIdentity(
                    host: identity.host,
                    port: 8443,
                    certificateSHA256: identity.certificateSHA256
                ),
                for: profileID
            )
        )
        XCTAssertFalse(
            store.isApproved(
                BrowserServerTrustIdentity(
                    host: identity.host,
                    port: identity.port,
                    certificateSHA256: "BB22"
                ),
                for: profileID
            )
        )
    }
}
