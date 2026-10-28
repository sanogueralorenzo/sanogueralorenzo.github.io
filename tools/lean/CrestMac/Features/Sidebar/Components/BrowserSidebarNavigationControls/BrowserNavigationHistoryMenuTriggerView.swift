import AppKit

/// Answers a history control's secondary clicks with the control's history as
/// an AppKit menu, built from the history at the moment it opens. The SwiftUI
/// button underneath keeps its ordinary primary click.
///
/// The menu is AppKit's alone, so nothing SwiftUI renders while it is open
/// reaches it. A SwiftUI context menu is rebuilt with its control: the
/// chevron's hover highlight changing as the pointer moved into the menu
/// replaced every item of the open menu, and AppKit laid the whole menu out
/// again for each replacement, holding the main thread for seconds.
@MainActor
final class BrowserNavigationHistoryMenuTriggerView: NSView {
    // MARK: - Variables

    /// The entries the menu lists, nearest first, read when it opens.
    var items: () -> [BrowserNavigationHistoryItem] = { [] }
    var emptyTitle: LocalizedStringResource = ""
    var choose: (BrowserNavigationHistoryItem) -> Void = { _ in }
    var showFullHistory: () -> Void = {}

    // MARK: - Actions - Mouse

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent, Self.isSecondary(event) else { return nil }
        return super.hitTest(point)
    }

    override func rightMouseDown(with event: NSEvent) {
        NSMenu.popUpContextMenu(makeMenu(), with: event, for: self)
    }

    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.control) else {
            super.mouseDown(with: event)
            return
        }
        NSMenu.popUpContextMenu(makeMenu(), with: event, for: self)
    }

    private static func isSecondary(_ event: NSEvent) -> Bool {
        switch event.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            true
        case .leftMouseDown, .leftMouseUp:
            event.modifierFlags.contains(.control)
        default:
            false
        }
    }

    // MARK: - Actions - Menu

    /// Opens the menu below the control, for an accessibility client's Show
    /// Menu, which comes with no pointer to place it at.
    func presentMenuBelowControl() {
        let below = NSPoint(x: bounds.minX, y: isFlipped ? bounds.maxY : bounds.minY)
        makeMenu().popUp(positioning: nil, at: below, in: self)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let entries = items()
        if entries.isEmpty {
            let empty = NSMenuItem(title: String(localized: emptyTitle), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for entry in entries {
            let item = NSMenuItem(title: entry.title, action: #selector(chooseEntry(_:)), keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
            item.toolTip = entry.url.absoluteString
            item.representedObject = entry
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let fullHistory = NSMenuItem(
            title: String(localized: "Show Full History"), action: #selector(showHistory(_:)), keyEquivalent: "")
        fullHistory.target = self
        fullHistory.image = NSImage(systemSymbolName: ShortcutCommand.showHistory.symbol, accessibilityDescription: nil)
        menu.addItem(fullHistory)
        return menu
    }

    @objc private func chooseEntry(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? BrowserNavigationHistoryItem else { return }
        choose(entry)
    }

    @objc private func showHistory(_ sender: NSMenuItem) {
        showFullHistory()
    }
}
