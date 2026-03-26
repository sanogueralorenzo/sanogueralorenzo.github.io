import AppKit
import Foundation

extension AppDelegate {
  func rebuildMenu(_ menu: NSMenu) {
    let data = menuDataStore.data
    menu.removeAllItems()

    menu.addItem(actionItem(title: "Codex", action: #selector(openCodexApp(_:))))
    menu.addItem(.separator())
    addCodexAgentSection(to: menu)
    menu.addItem(.separator())
    addRemoteSection(to: menu, data: data)
    menu.addItem(.separator())
    addProfilesSection(to: menu, data: data)
    menu.addItem(.separator())
    addThreadsSection(to: menu, data: data)
    menu.addItem(.separator())
    menu.addItem(actionItem(title: "Help", action: #selector(openHelp(_:))))
    menu.addItem(.separator())
    let quit = actionItem(title: "Quit", action: #selector(quit(_:)), keyEquivalent: "q")
    menu.addItem(quit)
  }

  private func addCodexAgentSection(to menu: NSMenu) {
    let data = menuDataStore.data
    menu.addItem(sectionHeaderItem(title: "Agents"))
    menu.addItem(actionItem(title: "Create", action: #selector(createCodexAgent(_:))))

    let viewItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
    let viewMenu = buildAgentJobsMenu(
      spikeJobs: data.spikeJobs,
      taskJobs: data.taskJobs,
      reviewJobs: data.reviewJobs
    )
    viewItem.isEnabled = viewMenu.items.contains(where: { !$0.isSeparatorItem })
    menu.addItem(viewItem)
    menu.setSubmenu(viewMenu, for: viewItem)

    menu.addItem(actionItem(title: "Settings", action: #selector(openCodexAgentSettings(_:))))
  }

  private func buildAgentJobsMenu(
    spikeJobs: [CodexCoreCLIClient.SpikeJob],
    taskJobs: [CodexCoreCLIClient.TaskJob],
    reviewJobs: [CodexCoreCLIClient.ReviewJob]
  ) -> NSMenu {
    let menu = NSMenu()
    let orderedSpikeJobs = spikeJobs.sorted { $0.createdAt > $1.createdAt }
    let orderedTaskJobs = taskJobs.sorted { $0.createdAt > $1.createdAt }
    let orderedReviewJobs = reviewJobs.sorted { $0.createdAt > $1.createdAt }

    if orderedSpikeJobs.isEmpty && orderedTaskJobs.isEmpty && orderedReviewJobs.isEmpty {
      menu.addItem(disabledItem(title: "No Saved Runs"))
      return menu
    }

    if !orderedSpikeJobs.isEmpty {
      menu.addItem(sectionHeaderItem(title: "Spikes"))
      for job in orderedSpikeJobs {
        let item = actionItem(
          title: "\(spikeJobStatusPrefix(for: job.status)) \(job.ticket)",
          action: #selector(openAgentURL(_:))
        )
        item.representedObject = job.issueUrl
        menu.addItem(item)
      }
    }

    if !orderedSpikeJobs.isEmpty && (!orderedTaskJobs.isEmpty || !orderedReviewJobs.isEmpty) {
      menu.addItem(.separator())
    }

    if !orderedTaskJobs.isEmpty {
      menu.addItem(sectionHeaderItem(title: "Tasks"))
      for job in orderedTaskJobs {
        if let prURL = job.prUrl {
          let item = actionItem(
            title: "\(taskJobStatusPrefix(for: job.status)) \(job.ticket)",
            action: #selector(openAgentURL(_:))
          )
          item.representedObject = prURL
          menu.addItem(item)
        } else {
          menu.addItem(disabledItem(title: "\(taskJobStatusPrefix(for: job.status)) \(job.ticket)"))
        }
      }
    }

    if !orderedTaskJobs.isEmpty && !orderedReviewJobs.isEmpty {
      menu.addItem(.separator())
    }

    if !orderedReviewJobs.isEmpty {
      menu.addItem(sectionHeaderItem(title: "Reviews"))
      for job in orderedReviewJobs {
        if let url = job.url {
          let item = actionItem(
            title: "\(reviewJobStatusPrefix(for: job.status)) \(job.repo)#\(job.number)",
            action: #selector(openAgentURL(_:))
          )
          item.representedObject = url
          menu.addItem(item)
        } else {
          menu.addItem(
            disabledItem(title: "\(reviewJobStatusPrefix(for: job.status)) \(job.repo)#\(job.number)")
          )
        }
      }
    }

    return menu
  }

  private func addRemoteSection(to menu: NSMenu, data: CodexMenuData) {
    menu.addItem(sectionHeaderItem(title: "Remote"))

    let action: Selector
    let title: String
    switch remoteCLI.menuAction(remoteStatus: data.remoteStatus, isLoading: data.isLoading) {
    case .install:
      title = "Install Remote…"
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

  private func addThreadsSection(to menu: NSMenu, data: CodexMenuData) {
    let sessionsItem = NSMenuItem(title: "Threads", action: nil, keyEquivalent: "")
    let sessionsMenu = NSMenu()

    if data.isLoading {
      sessionsMenu.addItem(disabledItem(title: "Loading..."))
    } else {
      switch data.sessionsStatus ?? .notInstalled {
      case .notInstalled:
        sessionsMenu.addItem(disabledItem(title: "Threads CLI not installed (codex-core)"))
      case .ready:
        sessionsMenu.addItem(
          sectionHeaderItem(title: "Auto-Remove", action: #selector(clearAutoRemoveSelection(_:))))
        sessionsMenu.addItem(actionItem(title: "Now", action: #selector(runAutoRemoveNow(_:))))
        sessionsMenu.addItem(autoRemoveDayMenuItem(days: 1))
        sessionsMenu.addItem(autoRemoveDayMenuItem(days: 3))
        sessionsMenu.addItem(autoRemoveDayMenuItem(days: 7))
        sessionsMenu.addItem(.separator())
      }
    }

    menu.addItem(sessionsItem)
    menu.setSubmenu(sessionsMenu, for: sessionsItem)
  }

  private func sectionHeaderItem(title: String, action: Selector = #selector(noopHeader(_:)))
    -> NSMenuItem
  {
    let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
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

  private func disabledItem(title: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    return item
  }

  private func taskJobStatusPrefix(
    for status: CodexCoreCLIClient.TaskJob.Status, trailingSpace: Bool = false
  ) -> String {
    let symbol: String
    switch status {
    case .completed:
      symbol = "✓"
    case .failed:
      symbol = "X"
    case .inProgress:
      symbol = "·"
    }
    return trailingSpace ? "\(symbol) " : symbol
  }

  private func spikeJobStatusPrefix(
    for status: CodexCoreCLIClient.SpikeJob.Status, trailingSpace: Bool = false
  ) -> String {
    let symbol: String
    switch status {
    case .completed:
      symbol = "✓"
    case .failed:
      symbol = "X"
    case .inProgress:
      symbol = "·"
    }
    return trailingSpace ? "\(symbol) " : symbol
  }

  private func taskJobStatusPrefix(
    for status: CodexCoreCLIClient.TaskJob.Status?,
    trailingSpace: Bool = false
  ) -> String {
    guard let status else {
      return ""
    }
    return taskJobStatusPrefix(for: status, trailingSpace: trailingSpace)
  }

  private func reviewJobStatusPrefix(for status: CodexCoreCLIClient.ReviewJob.Status) -> String {
    switch status {
    case .published:
      return "✓"
    case .needsAttention:
      return "X"
    case .inProgress:
      return "·"
    }
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

  private func autoRemoveDayMenuItem(days: Int) -> NSMenuItem {
    let item = NSMenuItem(
      title: "\(days) day" + (days == 1 ? "" : "s"),
      action: nil,
      keyEquivalent: ""
    )
    item.state = autoRemoveSettings.olderThanDays == days ? .on : .off
    let submenu = NSMenu()
    submenu.addItem(autoRemoveModeSubmenuItem(days: days, mode: .archive))
    submenu.addItem(autoRemoveModeSubmenuItem(days: days, mode: .delete))
    item.submenu = submenu
    return item
  }

  private func autoRemoveModeSubmenuItem(
    days: Int,
    mode: CodexCoreCLIClient.AutoRemoveMode
  ) -> NSMenuItem {
    let item = NSMenuItem(
      title: mode == .archive ? "Archive" : "Delete",
      action: #selector(setAutoRemoveSelection(_:)),
      keyEquivalent: ""
    )
    item.target = self
    item.representedObject = "\(days):\(mode.rawValue)"
    item.state =
      autoRemoveSettings.olderThanDays == days && autoRemoveSettings.mode == mode ? .on : .off
    return item
  }
}
