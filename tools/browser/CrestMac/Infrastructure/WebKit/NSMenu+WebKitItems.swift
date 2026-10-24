import AppKit

extension NSMenu {
    // MARK: - Variables

    /// WebKit's Download Image item, when the menu has one.
    var webKitDownloadImageItem: NSMenuItem? {
        items.first { $0.identifier == .webKitDownloadImage }
    }

    /// WebKit's Paste item, when the menu has one.
    var webKitPasteItem: NSMenuItem? {
        items.first { $0.identifier == .webKitPaste }
    }

    // MARK: - Actions - WebKit items

    /// Drops WebKit's selection search, which would leave Crest's own search.
    func removeWebKitSelectionSearch() {
        if let item = items.first(where: { $0.identifier == .webKitSearchWeb }) {
            removeItem(item)
        }
    }

    /// Names WebKit's open-link item for where Crest actually opens it,
    /// keeping its action and shortcut.
    func relabelWebKitLinkDestination() {
        items.first { $0.identifier == .webKitOpenLinkInNewWindow }?.title =
            String(localized: "Open Link in This Space")
    }
}
