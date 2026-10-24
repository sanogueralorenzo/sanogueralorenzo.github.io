/// The shortcut is bound to the command.
struct BrowserShortcutAssigned: BrowserShortcutAssignmentResult {
    // MARK: - Actions - Settings

    @MainActor
    func apply(
        to model: BrowserShortcutSettingsModel, recording shortcut: BrowserShortcut, for command: ShortcutCommand
    ) {
        model.validationIssue = nil
    }
}
