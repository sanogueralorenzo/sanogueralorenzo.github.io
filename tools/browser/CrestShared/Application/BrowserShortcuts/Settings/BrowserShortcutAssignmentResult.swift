/// What the core answered when a shortcut was bound to a command. Each answer
/// says what it does to the settings that recorded the shortcut, so recording
/// is `result.apply(to: model, …)`.
protocol BrowserShortcutAssignmentResult: Sendable {
    /// Shows the answer for `shortcut`, recorded for `command`, in `model`.
    @MainActor
    func apply(
        to model: BrowserShortcutSettingsModel, recording shortcut: BrowserShortcut, for command: ShortcutCommand)
}
