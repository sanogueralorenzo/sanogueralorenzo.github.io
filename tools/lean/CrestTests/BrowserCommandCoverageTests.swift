import XCTest

@testable import Crest

/// Every command the core names runs in the Mac shell, and every way the
/// core says a palette row activates has a way to run it. A kind left out
/// would quietly never be offered or never run.
@MainActor
final class BrowserCommandCoverageTests: XCTestCase {
    func testEveryDesktopCommandTheCoreNamesRunsInTheMacShell() {
        // Toggle Sidebar controls the mobile split view; the Mac sidebar
        // follows its hover presentation and has no such command.
        let missing = ShortcutCommand.all.filter { $0 != .toggleSidebar && BrowserMacCommand.of($0) == nil }.map(\.name)
        XCTAssertEqual(missing, [])
    }

    func testEveryActivationTheCoreNamesRunsInThePalette() {
        let missing = PaletteActivation.all.filter { BrowserCommandPaletteActivation.of($0) == nil }.map(\.name)
        XCTAssertEqual(missing, [])
    }
}
