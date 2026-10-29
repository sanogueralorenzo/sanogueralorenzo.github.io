import Foundation

/// What this process makes of the native command catalog: which commands the
/// device offers, each command's default keys here, and the numbered commands
/// by position.
extension ShortcutCommand {
    // MARK: - Variables

    /// Crest's default keys for the command on this device.
    var defaultShortcut: BrowserShortcut? {
        defaultShortcuts.first { $0.platform == .current }.map { BrowserShortcut($0.keys) }
    }

    // MARK: - Actions - Bindings

    /// The current binding, with catalog defaults for previews that supply no bindings.
    func shortcut(in bindings: [ShortcutCommand: ShortcutBinding]?) -> BrowserShortcut? {
        guard let bindings else { return defaultShortcut }
        return bindings[self]?.keys.flatMap(BrowserShortcut.init(boundKeys:))
    }

    // MARK: - Actions - Offering

    /// The whole feature must be available from WebKit. The active page's
    /// capabilities separately decide whether an offered command is enabled.
    @MainActor
    func isOffered(in state: CoreState) -> Bool {
        requiredCapability.map(state.offers) ?? true
    }

    // MARK: - Actions - Numbered selection

    /// The command that selects the `number`th item of `target`, counting from
    /// one. It reaches a visible sidebar stop or an available Space.
    static func selecting(_ target: NumberedSelectionTarget, number: Int) -> ShortcutCommand? {
        all.first { $0.selects == target && $0.number == number }
    }
}

// MARK: - Identifiable

extension ShortcutCommand: Identifiable {
    var id: String { name }
}
