import Foundation

/// What this process makes of the core's command catalog: which commands the
/// device offers, each command's default keys here, and the numbered commands
/// by position.
extension ShortcutCommand {
    // MARK: - Variables

    /// Crest's default keys for the command on this device.
    var defaultShortcut: BrowserShortcut? {
        defaultShortcuts.first { $0.platform == .current }.map { BrowserShortcut($0.keys) }
    }

    // MARK: - Actions - Offering

    /// Whether the device offers the command anywhere a person can find one,
    /// such as the menu bar and the launcher: the default engine or an engine
    /// a page is open on supports the command's whole feature. A command the
    /// person could not use anywhere is left out rather than shown dimmed,
    /// while one the shown page's engine lacks stays dimmed. The core applies
    /// the same rule to the commands that may hold a chord, which the shortcut
    /// settings list.
    @MainActor
    func isOffered(in state: CoreState) -> Bool {
        requiredCapability.map(state.offers) ?? true
    }

    // MARK: - Actions - Numbered selection

    /// The command that selects the `number`th item of `target`, counting from
    /// one. What it reaches is the core's `NumberedSelections` answer.
    static func selecting(_ target: NumberedSelectionTarget, number: Int) -> ShortcutCommand? {
        all.first { $0.selects == target && $0.number == number }
    }
}

// MARK: - Identifiable

extension ShortcutCommand: Identifiable {
    var id: String { name }
}
