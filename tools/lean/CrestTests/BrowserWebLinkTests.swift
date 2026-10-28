import Foundation
import XCTest

@testable import Crest

final class BrowserWebLinkTests: XCTestCase {
    func testExternalLinkEligibilityKeepsCrestsSchemeAndHostRules() {
        let cases: [(String?, String?, Bool)] = [
            ("HTTPS", "example.com", true), ("http", "example.com", true),
            ("https", "", false), ("file", nil, false),
            ("javascript", "example.com", false), (nil, "example.com", false),
            ("https", String(repeating: "a", count: 1_024), true),
            ("https", String(repeating: "a", count: 1_025), false),
        ]
        for (scheme, host, expected) in cases {
            XCTAssertEqual(ExternalWebLink(scheme: scheme, host: host).isAccepted, expected)
        }
    }

    func testEligibilityUsesTheAddressParsedByFoundation() throws {
        for address in ["http://example.com/path", "https://例え.テスト/path"] {
            XCTAssertTrue(ExternalWebLink.accepts(try XCTUnwrap(URL(string: address))))
        }
        for address in [
            "/relative", "https:/path", "mailto:person@example.com", "javascript:void(0)", "file:///tmp/example.html",
        ] {
            XCTAssertFalse(ExternalWebLink.accepts(try XCTUnwrap(URL(string: address))))
        }
    }
}
