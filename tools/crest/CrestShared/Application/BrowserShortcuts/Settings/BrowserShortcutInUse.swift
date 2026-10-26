/// Other commands hold the shortcut, so binding it waits for the person to
/// choose whether to take it from them.
struct BrowserShortcutInUse: BrowserShortcutAssignmentResult {
    // MARK: - Variables

    let commands: [ShortcutCommand]

    // MARK: - Actions - Settings

    @MainActor
    func apply(
        to model: BrowserShortcutSettingsModel, recording shortcut: BrowserShortcut, for command: ShortcutCommand
    ) {
        model.pendingConflict = BrowserShortcutPendingConflict(
            command: command,
            shortcut: shortcut,
            conflictingCommands: commands
        )
    }
}
