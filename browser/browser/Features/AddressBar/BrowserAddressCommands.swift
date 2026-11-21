import Foundation

@MainActor struct BrowserPaletteCommand {
    let title: String
    let aliases: String
    let symbol: String
    let shortcut: String
    let action: (BrowserStore) -> Void
    static let all: [BrowserPaletteCommand] = [
        .init(
            title: "New Tab", aliases: "create open", symbol: "plus", shortcut: "⌘T",
            action: { $0.presentAddress(newTab: true) }),
        .init(
            title: "New Window", aliases: "window", symbol: "macwindow.badge.plus", shortcut: "⌘N",
            action: { $0.owner.openWindow?(nil) }),
        .init(
            title: "Settings", aliases: "preferences options", symbol: "gearshape", shortcut: "⌘,",
            action: { $0.openSettings() }),
        .init(
            title: "History", aliases: "visited", symbol: "clock.arrow.circlepath", shortcut: "⌘Y",
            action: { $0.presentUtility(.history) }),
        .init(
            title: "Downloads", aliases: "files resume", symbol: "arrow.down.circle", shortcut: "⇧⌘J",
            action: { $0.presentUtility(.downloads) }),
        .init(
            title: "Reader Mode", aliases: "reading article", symbol: "doc.text", shortcut: "",
            action: { $0.activePage?.toggleReader() }),
        .init(
            title: "Translate Page", aliases: "translation language", symbol: "translate", shortcut: "⇧⌘L",
            action: { $0.activePage?.translationRequest &+= 1 }),
        .init(
            title: "Split with New Tab", aliases: "side by side", symbol: "rectangle.split.2x1", shortcut: "",
            action: { $0.beginSplit() }),
        .init(
            title: "Change Split Direction", aliases: "horizontal vertical", symbol: "rectangle.split.1x2",
            shortcut: "", action: { $0.changeSplitDirection() }),
        .init(
            title: "Leave Split View", aliases: "unsplit separate", symbol: "rectangle", shortcut: "",
            action: { $0.leaveSplit() }),
        .init(
            title: "Clear Tabs", aliases: "close current cleanup", symbol: "xmark", shortcut: "⇧⌘K",
            action: { $0.clearCurrentTabs() }),
        .init(
            title: "New Private Space", aliases: "incognito", symbol: "eye.slash", shortcut: "",
            action: { $0.savePrivateSpace() }),
        .init(
            title: "Import Browser Data", aliases: "bookmarks safari chrome zen arc firefox",
            symbol: "square.and.arrow.down", shortcut: "", action: { $0.importBrowserData() }),
        .init(
            title: "Export Browser Data", aliases: "backup bookmarks", symbol: "square.and.arrow.up", shortcut: "",
            action: { $0.exportBrowserData() }),
        .init(
            title: "Developer Tools", aliases: "inspect debugger console", symbol: "curlybraces", shortcut: "⌥⌘I",
            action: { $0.activePage?.showDeveloperTools() }),
        .init(
            title: "Reload", aliases: "refresh", symbol: "arrow.clockwise", shortcut: "⌘R",
            action: { $0.activePage?.webView.reload() }),
    ]
}
