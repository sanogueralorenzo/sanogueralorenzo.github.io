import AppKit
import SwiftUI

/// AppKit owns the menu's key-equivalent column and dispatches its selected action.
struct BrowserPlatformSpaceActionsMenu: NSViewRepresentable {
    // MARK: - Variables

    let sections: [[BrowserSpaceHeaderMenuItem]]
    let controlSize: CGFloat
    let symbolSize: CGFloat

    // MARK: - Actions - Drawing

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .regular)
        button.target = context.coordinator
        button.action = #selector(Coordinator.presentMenu(_:))
        button.isBordered = false
        button.bezelStyle = .inline
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .labelColor
        button.setAccessibilityRole(.menuButton)
        button.setAccessibilityLabel(String(localized: "Space actions"))
        button.setAccessibilityIdentifier("space-actions")
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.sections = sections
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        CGSize(width: controlSize, height: controlSize)
    }

    // MARK: - Types

    @MainActor
    final class Coordinator: NSObject {
        // MARK: - Variables

        var sections: [[BrowserSpaceHeaderMenuItem]] = []

        // MARK: - Actions - Menu

        @objc func presentMenu(_ sender: NSButton) {
            let menu = NSMenu()
            menu.autoenablesItems = false
            for (index, section) in sections.enumerated() {
                if index > 0 { menu.addItem(.separator()) }
                for entry in section { menu.addItem(item(entry)) }
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: sender)
        }

        private func item(_ entry: BrowserSpaceHeaderMenuItem) -> NSMenuItem {
            let item = NSMenuItem(
                title: String(localized: entry.title), action: #selector(choose(_:)),
                keyEquivalent: entry.shortcut.map { String($0.key.keyEquivalent.character) } ?? "")
            item.keyEquivalentModifierMask = entry.shortcut?.modifiers.appKitModifierFlags ?? []
            item.target = self
            item.representedObject = entry
            item.identifier = entry.identifier.map { NSUserInterfaceItemIdentifier($0) }
            item.isEnabled = entry.isEnabled
            item.image = NSImage(systemSymbolName: entry.symbol, accessibilityDescription: nil)
            if !entry.children.isEmpty {
                let submenu = NSMenu()
                submenu.autoenablesItems = false
                for child in entry.children { submenu.addItem(self.item(child)) }
                item.submenu = submenu
            }
            return item
        }

        @objc private func choose(_ sender: NSMenuItem) {
            (sender.representedObject as? BrowserSpaceHeaderMenuItem)?.action()
        }
    }
}
