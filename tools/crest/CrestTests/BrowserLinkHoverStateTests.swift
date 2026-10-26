import Foundation
import WebKit
import XCTest

@testable import Crest

final class BrowserLinkHoverStateTests: XCTestCase {
    func testInternationalHostAndDirectionalControlsStayUnambiguous() {
        let destination = BrowserLinkHoverDestination(
            resolvedURL: "https://bücher.example/a\u{202E}txt?q=%E2%80%AE#end")
        XCTAssertEqual(destination?.text, "https://xn--bcher-kva.example/a%E2%80%AEtxt?q=%E2%80%AE#end")
        XCTAssertFalse(destination?.text.contains("\u{202E}") ?? true)
    }
}

@MainActor
final class BrowserLinkHoverBridgeTests: XCTestCase {
}
