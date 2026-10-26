import AppKit
import Foundation
import XCTest

@testable import Crest

final class BrowserLinkContextCaptureTests: XCTestCase {
    func testOnlyWebSchemesAreCaptured() {
        let refused = [
            "javascript:alert(1)",
            "data:text/html,<b>hi</b>",
            "file:///etc/passwd",
            "mailto:someone@example.com",
            "about:blank",
            "crest-extension-install://chrome-web-store/abc",
            "https:///no-host",
        ]
        for href in refused {
            var policy = BrowserLinkContextCapture()
            policy.record(body: makeBody(href: href))
            XCTAssertNil(
                policy.take()?.linkURL,
                "\(href) is not a destination the new-tab path would accept."
            )
        }
    }

    private func makeBody(
        href: String? = nil,
        imageURL: String? = nil,
        selectionText: String? = nil,
        isEditable: Bool = false
    ) -> [String: Any] {
        var body: [String: Any] = [
            "version": BrowserLinkContextCapture.contractVersion,
            "token": 1,
            "editable": isEditable,
        ]
        body["href"] = href ?? NSNull()
        body["imageURL"] = imageURL ?? NSNull()
        body["selectionText"] = selectionText ?? NSNull()
        return body
    }
}
