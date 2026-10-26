import Foundation

/// Reads the fixed bindings the core publishes and resolves native keys.
@MainActor
final class BrowserShortcutStore {
    // MARK: - Variables

    private let core: CrestCore

    var offeredCommands: [ShortcutCommand] {
        core.state.shortcutBindings.map(\.command)
    }

    // MARK: - Initializers

    init(core: CrestCore) {
        self.core = core
    }

    convenience init() {
        self.init(core: CrestCore())
    }

    // MARK: - Actions - Bindings

    func shortcut(for command: ShortcutCommand) -> BrowserShortcut? {
        command.shortcut(in: core.state.shortcuts)
    }

    func commands(assignedTo shortcut: BrowserShortcut) -> [ShortcutCommand] {
        let keys = shortcut.keys
        return core.state.shortcutBindings.filter { $0.keys == keys }.map(\.command)
    }
}
