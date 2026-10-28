import AppKit
import XCTest

@testable import Crest

final class BrowserShortcutTests: XCTestCase {
    @MainActor
    func testNativeDispatchUsesFixedBindingsAndLeavesDisabledCommandsToTheResponder() throws {
        let store = BrowserShortcutStore()
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero,
                modifierFlags: [.command, .shift], timestamp: 0, windowNumber: 0, context: nil,
                characters: "i", charactersIgnoringModifiers: "i", isARepeat: false, keyCode: 34))
        XCTAssertEqual(store.command(for: event, isEnabled: { _ in true }), .toggleDeveloperToolbar)
        XCTAssertNil(store.command(for: event, isEnabled: { _ in false }))
    }

    @MainActor
    func testDefaultZoomAliasLeavesDisabledCommandsToTheResponder() throws {
        let store = BrowserShortcutStore()
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero,
                modifierFlags: [.command], timestamp: 0, windowNumber: 0, context: nil,
                characters: "=", charactersIgnoringModifiers: "=", isARepeat: false, keyCode: 24))
        XCTAssertEqual(store.command(for: event, isEnabled: { _ in true }), .zoomIn)
        XCTAssertNil(store.command(for: event, isEnabled: { _ in false }))
    }

    func testShortcutRequiresAtLeastOneSupportedModifier() {
        XCTAssertFalse(shortcut("t", []).isValid)
        XCTAssertTrue(shortcut("t", [.command]).isValid)
        XCTAssertTrue(special(.leftArrow, [.control, .option]).isValid)
    }

    @MainActor
    func testCrestShortcutAssignmentsCanBeResolvedBeforeExtensions() throws {
        let store = BrowserShortcutStore()
        let newTab = try XCTUnwrap(store.shortcut(for: .newTab))

        XCTAssertEqual(store.commands(assignedTo: newTab), [.newTab])
        XCTAssertTrue(store.commands(assignedTo: shortcut("g", [.option])).isEmpty)
    }

    private func shortcut(
        _ character: Character,
        _ modifiers: ShortcutModifiers
    ) -> BrowserShortcut {
        BrowserShortcut(key: .character(character), modifiers: modifiers)
    }

    private func special(
        _ key: ShortcutSpecialKey,
        _ modifiers: ShortcutModifiers
    ) -> BrowserShortcut {
        BrowserShortcut(key: .special(key), modifiers: modifiers)
    }
}
