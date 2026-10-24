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

    @MainActor
    func testDefaultZoomAliasNeverOverridesAnExplicitAssignment() throws {
        let store = BrowserShortcutStore()
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero,
                modifierFlags: [.command], timestamp: 0, windowNumber: 0, context: nil,
                characters: "=", charactersIgnoringModifiers: "=", isARepeat: false, keyCode: 24))
        XCTAssertEqual(store.command(for: event, isEnabled: { _ in true }), .zoomIn)
        XCTAssertTrue(
            store.assign(BrowserShortcut(key: .character("="), modifiers: .command), to: .newTab)
                is BrowserShortcutAssigned)
        XCTAssertEqual(store.command(for: event, isEnabled: { _ in true }), .newTab)
        XCTAssertNil(store.command(for: event, isEnabled: { $0 != .newTab }))
        store.clearShortcut(for: .newTab)
        store.clearShortcut(for: .zoomIn)
        XCTAssertNil(store.command(for: event, isEnabled: { _ in true }))
    }

    func testShortcutRequiresAtLeastOneSupportedModifier() {
        XCTAssertFalse(shortcut("t", []).isValid)
        XCTAssertTrue(shortcut("t", [.command]).isValid)
        XCTAssertTrue(special(.leftArrow, [.control, .option]).isValid)
    }

    @MainActor
    func testShortcutSearchUsesCurrentBindingsAndFindsUnassignedCommands() {
        let store = BrowserShortcutStore()
        let custom = shortcut("g", [.command, .option])
        XCTAssertTrue(store.assign(custom, to: .newTab) is BrowserShortcutAssigned)

        XCTAssertEqual(store.commands(matching: "option g"), [.newTab])
        XCTAssertTrue(store.commands(matching: "unassigned").contains(.duplicateTab))
        XCTAssertFalse(store.commands(matching: "command t").contains(.newTab))
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
