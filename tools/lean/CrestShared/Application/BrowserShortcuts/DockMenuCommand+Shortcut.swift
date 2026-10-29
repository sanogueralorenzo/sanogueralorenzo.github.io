extension DockMenuCommand {
    var command: ShortcutCommand {
        self == .newPrivateWindow ? .newPrivateWindow : .newWindow
    }
}
