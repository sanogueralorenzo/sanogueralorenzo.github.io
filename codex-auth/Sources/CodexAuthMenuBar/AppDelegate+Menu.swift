import AppKit
import CodexAuthCore
import Foundation

extension AppDelegate {
    func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: "", action: #selector(noopHeader(_:)), keyEquivalent: "")
        header.attributedTitle = NSAttributedString(
            string: "Codex Auth",
            attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)]
        )
        header.target = self
        header.isEnabled = true
        menu.addItem(header)

        let currentName = (try? manager.currentProfileName())
        let profiles = (try? manager.listProfiles()) ?? []
        menu.addItem(.separator())

        if !profiles.isEmpty {
            for normalizedName in profiles {
                let item = NSMenuItem(title: displayProfileName(normalizedName),
                                      action: #selector(useNamedProfile(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.representedObject = normalizedName
                item.state = (normalizedName == currentName) ? .on : .off
                menu.addItem(item)
            }
        }

        let add = NSMenuItem(title: "Add", action: #selector(addProfileFromCurrent(_:)), keyEquivalent: "")
        add.target = self
        menu.addItem(add)

        menu.addItem(.separator())

        let removeItem = NSMenuItem(title: "Remove", action: nil, keyEquivalent: "")
        let removeMenu = NSMenu()
        if profiles.isEmpty {
            removeItem.isEnabled = false
        } else {
            for normalizedName in profiles {
                let subItem = NSMenuItem(title: displayProfileName(normalizedName),
                                         action: #selector(removeNamedProfile(_:)),
                                         keyEquivalent: "")
                subItem.target = self
                subItem.representedObject = normalizedName
                removeMenu.addItem(subItem)
            }
        }
        menu.addItem(removeItem)
        menu.setSubmenu(removeMenu, for: removeItem)

        menu.addItem(.separator())

        let help = NSMenuItem(title: "Help", action: #selector(openHelp(_:)), keyEquivalent: "")
        help.target = self
        menu.addItem(help)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }
}
