protocol BrowserShortcutSearchProviding {
    func matches(
        _ command: ShortcutCommand,
        currentShortcut: BrowserShortcut?,
        query: String
    ) -> Bool
}
