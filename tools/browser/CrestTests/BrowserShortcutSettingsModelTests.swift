import XCTest

@testable import Crest

@MainActor
final class BrowserShortcutSettingsModelTests: XCTestCase {
    func testCrestConflictWaitsForConfirmationBeforeReplacingAssignments() {
        let fixture = makeFixture()
        let shortcut = BrowserShortcut(
            key: .character("y"),
            modifiers: [.command, .shift]
        )
        XCTAssertTrue(
            fixture.shortcuts.assign(shortcut, to: .newTab) is BrowserShortcutAssigned
        )

        fixture.model.record(shortcut, for: .newWindow)

        XCTAssertEqual(
            fixture.model.pendingConflict,
            BrowserShortcutPendingConflict(
                command: .newWindow,
                shortcut: shortcut,
                conflictingCommands: [.newTab]
            )
        )
        XCTAssertEqual(
            fixture.shortcuts.shortcut(for: .newTab),
            shortcut
        )

        fixture.model.replacePendingConflict()

        XCTAssertNil(fixture.shortcuts.shortcut(for: .newTab))
        XCTAssertEqual(
            fixture.shortcuts.shortcut(for: .newWindow),
            shortcut
        )
        XCTAssertNil(fixture.model.pendingConflict)
    }

    func testCancelingCrestConflictPreservesBothExistingAssignments() {
        let fixture = makeFixture()
        let shortcut = BrowserShortcut(
            key: .character("y"),
            modifiers: [.command, .shift]
        )
        XCTAssertTrue(
            fixture.shortcuts.assign(shortcut, to: .newTab) is BrowserShortcutAssigned
        )

        fixture.model.record(shortcut, for: .newWindow)
        fixture.model.cancelPendingConflict()

        XCTAssertEqual(fixture.shortcuts.shortcut(for: .newTab), shortcut)
        XCTAssertEqual(
            fixture.shortcuts.shortcut(for: .newWindow),
            ShortcutCommand.newWindow.defaultShortcut
        )
        XCTAssertNil(fixture.model.pendingConflict)
    }

    private func makeFixture() -> (shortcuts: BrowserShortcutStore, model: BrowserShortcutSettingsModel) {
        let shortcuts = BrowserShortcutStore()
        let model = BrowserShortcutSettingsModel(shortcuts: shortcuts, searchProvider: SearchProvider())
        return (shortcuts, model)
    }
    private struct SearchProvider: BrowserShortcutSearchProviding {
        func matches(_ command: ShortcutCommand, currentShortcut: BrowserShortcut?, query: String) -> Bool {
            query.isEmpty || command.name.localizedCaseInsensitiveContains(query)
        }
    }
}
