import AppKit
import Foundation

extension AppDelegate {
  func rebuildMenu(_ menu: NSMenu) {
    let data = menuDataStore.data
    menu.removeAllItems()

    addProfilesSection(to: menu, data: data)
    menu.addItem(.separator())
    addRemoteSection(to: menu, data: data)
    menu.addItem(.separator())
    let quit = actionItem(title: "Quit", action: #selector(quit(_:)), keyEquivalent: "q")
    menu.addItem(quit)
  }

  private func addRemoteSection(to menu: NSMenu, data: CodexMenuData) {
    menu.addItem(sectionHeaderItem(title: "Remote"))

    let action: Selector
    let title: String
    switch remoteCLI.menuAction(remoteStatus: data.remoteStatus, isLoading: data.isLoading) {
    case .install:
      title = "Install Remote..."
      action = #selector(installCodexRemote(_:))
    case .start:
      title = "Start"
      action = #selector(startCodexRemote(_:))
    case .stop:
      title = "Stop"
      action = #selector(stopCodexRemote(_:))
    }

    menu.addItem(actionItem(title: title, action: action))
  }

  private func addProfilesSection(to menu: NSMenu, data: CodexMenuData) {
    menu.addItem(sectionHeaderItem(title: "Profiles"))

    let authMenuProfiles = authCLI.menuProfiles(
      currentProfileName: data.currentProfileName,
      profiles: data.profiles,
      isLoading: data.isLoading
    )

    for profile in authMenuProfiles {
      let profileItem = NSMenuItem(
        title: displayProfileName(profile.normalizedName), action: nil, keyEquivalent: "")
      profileItem.state = profile.isCurrent ? .on : .off

      let profileMenu = NSMenu()
      for action in profile.actions {
        profileMenu.addItem(authProfileActionItem(for: action, profileName: profile.normalizedName))
      }

      menu.addItem(profileItem)
      menu.setSubmenu(profileMenu, for: profileItem)
    }

    menu.addItem(actionItem(title: "Add", action: #selector(addProfileFromCurrent(_:))))
  }

  private func sectionHeaderItem(title: String) -> NSMenuItem {
    let item = NSMenuItem(title: "", action: #selector(noopHeader(_:)), keyEquivalent: "")
    item.attributedTitle = NSAttributedString(
      string: title,
      attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)]
    )
    item.target = self
    item.isEnabled = true
    return item
  }

  private func actionItem(title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem
  {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
    item.target = self
    return item
  }

  private func authProfileActionItem(
    for action: CodexAuthCLIClient.MenuProfileAction,
    profileName: String
  ) -> NSMenuItem {
    let item: NSMenuItem

    switch action {
    case .use:
      item = NSMenuItem(
        title: "Use",
        action: #selector(useNamedProfile(_:)),
        keyEquivalent: "")
    case .remove:
      item = NSMenuItem(
        title: "Remove",
        action: #selector(removeNamedProfile(_:)),
        keyEquivalent: "")
    }

    item.target = self
    item.representedObject = profileName
    return item
  }
}
