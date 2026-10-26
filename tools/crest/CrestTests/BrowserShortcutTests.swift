import AppKit
import XCTest

@testable import Crest

final class BrowserShortcutTests: XCTestCase {
    @MainActor
    func testNativeDispatchUsesCurrentOverridesAndLeavesDisabledCommandsToTheResponder() throws {
        let store = BrowserShortcutStore()
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero,
                modifierFlags: [.command, .shift], timestamp: 0, windowNumber: 0, context: nil,
                characters: "i", charactersIgnoringModifiers: "i", isARepeat: false, keyCode: 34))
        XCTAssertEqual(store.command(for: event, isEnabled: { _ in true }), .toggleDeveloperToolbar)
        XCTAssertNil(store.command(for: event, isEnabled: { _ in false }))
        store.clearShortcut(for: .toggleDeveloperToolbar)
        XCTAssertNil(store.command(for: event, isEnabled: { _ in true }))
        XCTAssertTrue(
            store.assign(BrowserShortcut(key: .character("i"), modifiers: [.command, .shift]), to: .newTab)
                is BrowserShortcutAssigned)
        XCTAssertEqual(store.command(for: event, isEnabled: { _ in true }), .newTab)
    }

    private func special(
        _ key: ShortcutSpecialKey,
        _ modifiers: ShortcutModifiers
    ) -> BrowserShortcut {
        BrowserShortcut(key: .special(key), modifiers: modifiers)
    }
}
