import XCTest

@testable import Crest

/// Every command the core names runs in the Mac shell, and every way the
/// core says a palette row activates has a way to run it. A kind left out
/// would quietly never be offered or never run.
@MainActor
final class BrowserCommandCoverageTests: XCTestCase {
    func testEveryCommandTheCoreNamesRunsInTheMacShell() {
        let missing = ShortcutCommand.all.filter { BrowserMacCommand.of($0) == nil }.map(\.name)
        XCTAssertEqual(missing, [])
    }

    func testEveryActivationTheCoreNamesRunsInThePalette() {
        let missing = PaletteActivation.all.filter { BrowserCommandPaletteActivation.of($0) == nil }.map(\.name)
        XCTAssertEqual(missing, [])
    }
}
