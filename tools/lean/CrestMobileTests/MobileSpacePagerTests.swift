import SwiftUI
import XCTest

@testable import CrestMobile

@MainActor
final class MobileSpacePagerTests: XCTestCase {
    /// Only a scroll a person drives may settle the pager on another Space.
    ///
    /// With a hardware keyboard, iPadOS keyboard focus takes Tab and Shift-Tab
    /// from a web page's one-line field before the page sees them, and can move
    /// to the place UIKit keeps for another Space's page in this scroll view.
    /// Showing it scrolls the pager with no finger down, and settling there
    /// used to switch the Space.
    func testOnlyAScrollAPersonDrivesMayChooseTheSpace() {
        let progress = TouchSpacePagerProgress()
        let ids = [UUID(), UUID()]

        progress.update(phase: .decelerating, ids: ids, presentation: nil)
        progress.update(phase: .idle, ids: ids, presentation: nil)
        XCTAssertFalse(progress.isPersonDriven, "Keyboard focus moved the pager, so the Space stays.")

        progress.update(phase: .interacting, ids: ids, presentation: nil)
        progress.update(phase: .decelerating, ids: ids, presentation: nil)
        progress.update(phase: .idle, ids: ids, presentation: nil)
        XCTAssertTrue(progress.isPersonDriven, "A swipe chooses the Space it settles on.")

        progress.update(phase: .animating, ids: ids, presentation: nil)
        progress.update(phase: .idle, ids: ids, presentation: nil)
        XCTAssertFalse(progress.isPersonDriven, "A programmatic scroll chooses no Space either.")
    }
}
