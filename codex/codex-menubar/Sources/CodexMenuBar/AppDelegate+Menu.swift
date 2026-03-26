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
    menu.addItem(sectionHeaderItem(title: "Agents"))
    menu.addItem(actionItem(title: "Create", action: #selector(createCodexAgent(_:))))

    let viewItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
    let viewMenu = NSMenu()
    let runningTasks = CodexAgentMockData.runningTasks
    let recentTasks = CodexAgentMockData.recentTasks

    if runningTasks.isEmpty && recentTasks.isEmpty {
      viewItem.isEnabled = false
    } else {
      for task in runningTasks {
        let taskItem = NSMenuItem(title: task.ticket, action: nil, keyEquivalent: "")
        viewMenu.addItem(taskItem)
        viewMenu.setSubmenu(agentTaskMenu(for: task, isRecentTask: false), for: taskItem)
      }

      if !runningTasks.isEmpty && !recentTasks.isEmpty {
        viewMenu.addItem(.separator())
      }

      for task in recentTasks {
        let taskItem = NSMenuItem(
          title: "\(agentRecentTaskPrefix(for: task.status)) \(task.ticket)",
          action: nil,
          keyEquivalent: ""
        )
        viewMenu.addItem(taskItem)
        viewMenu.setSubmenu(agentTaskMenu(for: task, isRecentTask: true), for: taskItem)
      }
    }
    menu.addItem(viewItem)
    menu.setSubmenu(viewMenu, for: viewItem)

    let reviewItem = NSMenuItem(title: "Review", action: nil, keyEquivalent: "")
    let reviewMenu = NSMenu()
    let reviewJobs = menuDataStore.data.reviewJobs
    let reviewPullRequests = menuDataStore.data.reviewPullRequests

    if menuDataStore.data.isLoading {
      let loadingItem = NSMenuItem(title: "Loading...", action: nil, keyEquivalent: "")
      loadingItem.isEnabled = false
      reviewMenu.addItem(loadingItem)
    } else if reviewPullRequests.isEmpty {
      let emptyItem = NSMenuItem(title: "No Open PRs", action: nil, keyEquivalent: "")
      emptyItem.isEnabled = false
      reviewMenu.addItem(emptyItem)
    } else {
      let latestReviewJobByPullRequestURL = latestReviewJobsByPullRequestURL(reviewJobs)
      let groupedPullRequests = groupReviewPullRequests(reviewPullRequests)

      for (index, group) in groupedPullRequests.enumerated() {
        let repositoryItem = NSMenuItem(
          title: group.repository,
          action: #selector(openReviewRepository(_:)),
          keyEquivalent: "")
        repositoryItem.target = self
        repositoryItem.representedObject = group.repositoryURL
        repositoryItem.attributedTitle = NSAttributedString(
          string: group.repository,
          attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)]
        )
        reviewMenu.addItem(repositoryItem)

        for pullRequest in group.pullRequests {
          let markerPrefix = reviewPullRequestStatusPrefix(
            for: latestReviewJobByPullRequestURL[pullRequest.url]?.status
          )
          let item = NSMenuItem(
            title: "\(markerPrefix)\(pullRequest.shortMenuTitle)",
            action: #selector(reviewPullRequest(_:)),
            keyEquivalent: "")
          item.target = self
          item.representedObject = pullRequest.url
          reviewMenu.addItem(item)
        }

        if index < groupedPullRequests.count - 1 {
          reviewMenu.addItem(.separator())
        }
      }
    }
    menu.addItem(reviewItem)
    menu.setSubmenu(reviewMenu, for: reviewItem)

    menu.addItem(actionItem(title: "Settings", action: #selector(openCodexAgentSettings(_:))))
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
        sessionsMenu.addItem(sectionHeaderItem(title: "Floating"))
        sessionsMenu.addItem(actionItem(title: "Start", action: #selector(startFloating(_:))))
        sessionsMenu.addItem(.separator())
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

  private func latestReviewJobsByPullRequestURL(
    _ reviewJobs: [CodexCoreCLIClient.ReviewJob]
  ) -> [String: CodexCoreCLIClient.ReviewJob] {
    var jobsByURL: [String: CodexCoreCLIClient.ReviewJob] = [:]
    for job in reviewJobs.sorted(by: { $0.createdAt > $1.createdAt }) {
      guard let url = job.url, jobsByURL[url] == nil else {
        continue
      }
      jobsByURL[url] = job
    }
    return jobsByURL
  }

  private func groupReviewPullRequests(
    _ pullRequests: [CodexCoreCLIClient.ReviewPullRequest]
  ) -> [(
    repository: String, repositoryURL: String, pullRequests: [CodexCoreCLIClient.ReviewPullRequest]
  )] {
    var groupedPullRequests:
      [(
        repository: String, repositoryURL: String,
        pullRequests: [CodexCoreCLIClient.ReviewPullRequest]
      )] = []
    var groupedPullRequestIndexByRepository: [String: Int] = [:]

    for pullRequest in pullRequests {
      if let existingIndex = groupedPullRequestIndexByRepository[pullRequest.repositoryFullName] {
        groupedPullRequests[existingIndex].pullRequests.append(pullRequest)
        continue
      }

      groupedPullRequestIndexByRepository[pullRequest.repositoryFullName] =
        groupedPullRequests.count
      groupedPullRequests.append(
        (
          repository: pullRequest.repositoryFullName,
          repositoryURL: pullRequest.repositoryURL,
          pullRequests: [pullRequest]
        ))
    }

    for index in groupedPullRequests.indices {
      groupedPullRequests[index].pullRequests.sort { left, right in
        left.createdAt > right.createdAt
      }
    }

    return groupedPullRequests
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

  private func agentTaskMenu(for task: CodexAgentMockTask, isRecentTask: Bool) -> NSMenu {
    let taskMenu = baseAgentTaskMenu(for: task)
    if isRecentTask {
      taskMenu.addItem(
        agentTaskActionItem(
          title: "Re-run Task",
          action: #selector(rerunCodexAgentTask(_:)),
          ticket: task.ticket))
    } else {
      let pauseOrResumeTitle = task.isPaused ? "Resume Task" : "Pause Task"
      taskMenu.addItem(
        agentTaskActionItem(
          title: pauseOrResumeTitle,
          action: #selector(togglePauseCodexAgentTask(_:)),
          ticket: task.ticket))
      taskMenu.addItem(
        agentTaskActionItem(
          title: "Delete Task",
          action: #selector(deleteCodexAgentTask(_:)),
          ticket: task.ticket))
    }
    return taskMenu
  }

  private func agentRecentTaskPrefix(for status: CodexAgentMockTask.Status) -> String {
    switch status {
    case .completed:
      return "✓"
    case .failed:
      return "X"
    default:
      return "•"
    }
  }

  private func reviewPullRequestStatusPrefix(for state: CodexCoreCLIClient.ReviewJob.Status?)
    -> String
  {
    guard let state else {
      return ""
    }
    switch state {
    case .published:
      return "✓ "
    case .needsAttention:
      return "X "
    case .inProgress:
      return "· "
    }
  }

  private func baseAgentTaskMenu(for task: CodexAgentMockTask) -> NSMenu {
    let taskMenu = NSMenu()

    let statusItem = NSMenuItem(
      title: "Status: \(task.status.rawValue)", action: nil, keyEquivalent: "")
    statusItem.isEnabled = false
    taskMenu.addItem(statusItem)
    taskMenu.addItem(.separator())
    taskMenu.addItem(
      agentTaskActionItem(
        title: "View Task",
        action: #selector(viewCodexAgentTask(_:)),
        ticket: task.ticket))

    return taskMenu
  }

  private func agentTaskActionItem(title: String, action: Selector, ticket: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    item.representedObject = ticket
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
      (autoRemoveSettings.olderThanDays == days && autoRemoveSettings.mode == mode) ? .on : .off
    return item
  }
}
