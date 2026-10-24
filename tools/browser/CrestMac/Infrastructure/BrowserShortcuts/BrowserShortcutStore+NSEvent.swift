import AppKit

extension BrowserShortcutStore {
    /// Resolve live assignments before dispatch, including unassigned defaults.
    /// Disabled commands leave the event available to the focused native control.
    func command(for event: NSEvent, isEnabled: (ShortcutCommand) -> Bool) -> ShortcutCommand? {
        guard event.type == .keyDown, let shortcut = BrowserShortcut(event: event), shortcut.isValid else { return nil }
        let assigned = commands(assignedTo: shortcut)
        if !assigned.isEmpty { return assigned.first(where: isEnabled) }
        // Match AppKit's implicit Shift for the default plus key equivalent.
        if ["=", "+"].contains(event.charactersIgnoringModifiers ?? ""),
            shortcut.modifiers == .command || shortcut.modifiers == [.command, .shift],
            self.shortcut(for: .zoomIn) == ShortcutCommand.zoomIn.defaultShortcut,
            isEnabled(.zoomIn)
        {
            return .zoomIn
        }
        return nil
    }
}
