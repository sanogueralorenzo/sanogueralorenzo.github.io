import Foundation
import XCTest

@testable import Crest

final class BrowserDownloadDestinationTests: XCTestCase {
    func testRemovesWindowsTraversalControlCharactersAndHiddenEdges() {
        XCTAssertEqual(
            BrowserDownloadDestination.safeFilename(from: "..\\..\\.pay\u{0}load.txt. "),
            "payload.txt"
        )
        XCTAssertEqual(BrowserDownloadDestination.safeFilename(from: "../.."), "download")
    }

}
