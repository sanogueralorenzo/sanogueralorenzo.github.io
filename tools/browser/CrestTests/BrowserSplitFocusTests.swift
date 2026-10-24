import Foundation
import XCTest

@testable import Crest

/// The guard set behind pointer-driven Split View focus.
///
/// The tracking area and the event monitor that feed it are AppKit machinery no
/// test can drive, which is exactly why the decision they consult is a pure
/// function. These tests are the contract for when focus is allowed to move.
final class BrowserSplitFocusTests: XCTestCase {

    /// Focus is selection, and the selection observer resigns address focus, so
    /// a pointer drifting across a card while someone types a URL would discard
    /// what they had typed.
    func testHoverNeverInterruptsAddressBarTyping() {
        XCTAssertFalse(
            BrowserSplitPageSurface.focusesOnHover(
                followsMouse: true,
                isCardFocused: false,
                isAddressEditing: true,
                isDraggingSidebarItem: false,
                isCarryingCard: false,
                isCommandPalettePresented: false
            )
        )
    }

    func testHoverStandsAsideForADragInFlightAndForTheCommandPalette() {
        XCTAssertFalse(
            BrowserSplitPageSurface.focusesOnHover(
                followsMouse: true,
                isCardFocused: false,
                isAddressEditing: false,
                isDraggingSidebarItem: true,
                isCarryingCard: false,
                isCommandPalettePresented: false
            )
        )
        XCTAssertFalse(
            BrowserSplitPageSurface.focusesOnHover(
                followsMouse: true,
                isCardFocused: false,
                isAddressEditing: false,
                isDraggingSidebarItem: false,
                isCarryingCard: false,
                isCommandPalettePresented: true
            )
        )
    }

    /// A carried card crosses every neighbour on its way to a new slot, and the
    /// card somebody is holding already took focus at the pickup. Focus arriving
    /// at each column it passes over would reselect the split several times per
    /// gesture.
    func testHoverStandsAsideForACardBeingCarried() {
        XCTAssertFalse(
            BrowserSplitPageSurface.focusesOnHover(
                followsMouse: true,
                isCardFocused: false,
                isAddressEditing: false,
                isDraggingSidebarItem: false,
                isCarryingCard: true,
                isCommandPalettePresented: false
            )
        )
        XCTAssertFalse(
            BrowserSplitPageSurface.focusesOnClick(
                isCardFocused: false,
                isDraggingSidebarItem: false,
                isCarryingCard: true,
                isCommandPalettePresented: false
            )
        )
    }

    /// Click-to-focus is how Split View works rather than a behaviour to opt
    /// into, so the preference has no say in it — it is not even an input.
    func testClickFocusesAnUnfocusedCardRegardlessOfTheHoverSetting() {
        XCTAssertTrue(
            BrowserSplitPageSurface.focusesOnClick(
                isCardFocused: false,
                isDraggingSidebarItem: false,
                isCarryingCard: false,
                isCommandPalettePresented: false
            )
        )
    }

    /// A deliberate click into a card is a decision to leave the address field,
    /// which is why address editing is not a click guard the way it is a hover
    /// guard.
    func testClickIsRefusedOnlyByFocusADragOrThePalette() {
        XCTAssertFalse(
            BrowserSplitPageSurface.focusesOnClick(
                isCardFocused: true,
                isDraggingSidebarItem: false,
                isCarryingCard: false,
                isCommandPalettePresented: false
            )
        )
        XCTAssertFalse(
            BrowserSplitPageSurface.focusesOnClick(
                isCardFocused: false,
                isDraggingSidebarItem: true,
                isCarryingCard: false,
                isCommandPalettePresented: false
            )
        )
        XCTAssertFalse(
            BrowserSplitPageSurface.focusesOnClick(
                isCardFocused: false,
                isDraggingSidebarItem: false,
                isCarryingCard: false,
                isCommandPalettePresented: true
            )
        )
    }
}

/// The registry that turns a mouse-down location into the card it landed in.
@MainActor
final class BrowserSplitCardFrameRegistryTests: XCTestCase {

    func testACardThatLeavesTheRowStopsClaimingItsOldFrame() {
        let registry = BrowserSplitCardFrameRegistry()
        let tabID = UUID()
        registry.register(CGRect(x: 0, y: 0, width: 400, height: 600), for: tabID)

        registry.removeFrame(for: tabID)

        XCTAssertNil(registry.frame(for: tabID))
        XCTAssertNil(registry.tabID(containing: CGPoint(x: 12, y: 40)))
    }
}
