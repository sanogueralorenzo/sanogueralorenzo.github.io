import XCTest

@testable import Crest

final class BrowserShortcutPolicyTests: XCTestCase {
    func testSearchPolicyRequiresEveryTermAndExactSingleCharacterTokens() {
        let fields = [
            "Copy Page Link",
            "Page",
            "copy url address clipboard",
            "command shift c",
        ]

        XCTAssertTrue(
            BrowserShortcutSearchDocument(fields: fields).matches("copy url")
        )
        XCTAssertTrue(
            BrowserShortcutSearchDocument(fields: fields).matches("command shift c")
        )
        XCTAssertFalse(
            BrowserShortcutSearchDocument(fields: fields).matches("command shift p")
        )
        XCTAssertTrue(
            BrowserShortcutSearchDocument(fields: fields).matches("")
        )
    }

    func testExtensionSearchPreservesSingleTrimmedPhraseContainment() {
        let fields = [
            "Reader Tools",
            "Capture Article",
            "capture",
        ]

        XCTAssertTrue(
            BrowserShortcutSearchDocument(fields: fields).containsTrimmedPhrase("  reader tools  ")
        )
        XCTAssertTrue(
            BrowserShortcutSearchDocument(fields: fields).containsTrimmedPhrase("CAPTURE ARTICLE")
        )
        XCTAssertFalse(
            BrowserShortcutSearchDocument(fields: fields).containsTrimmedPhrase("reader capture")
        )
        XCTAssertTrue(
            BrowserShortcutSearchDocument(fields: fields).containsTrimmedPhrase("   ")
        )
    }
}
