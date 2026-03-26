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
    let viewMenu = buildTaskJobsMenu(taskJobs: data.taskJobs)
    viewItem.isEnabled = viewMenu.items.contains(where: { !$0.isSeparatorItem })
    menu.addItem(viewItem)
    menu.setSubmenu(viewMenu, for: viewItem)

    let taskItem = NSMenuItem(title: "Task", action: nil, keyEquivalent: "")
    let taskMenu = buildTaskCandidatesMenu(
      taskJobs: data.taskJobs, taskCandidates: data.taskCandidates)
    menu.addItem(taskItem)
    menu.setSubmenu(taskMenu, for: taskItem)

    let reviewItem = NSMenuItem(title: "Review", action: nil, keyEquivalent: "")
    let reviewMenu = buildReviewMenu(
      reviewJobs: data.reviewJobs, reviewPullRequests: data.reviewPullRequests)
    menu.addItem(reviewItem)
    menu.setSubmenu(reviewMenu, for: reviewItem)

    menu.addItem(actionItem(title: "Settings", action: #selector(openCodexAgentSettings(_:))))
  }

  private func buildTaskJobsMenu(taskJobs: [CodexCoreCLIClient.TaskJob]) -> NSMenu {
    let menu = NSMenu()
    let runningJobs =
      taskJobs
      .filter { $0.status == .inProgress }
      .sorted { $0.createdAt > $1.createdAt }
    let recentJobs =
      taskJobs
      .filter { $0.status != .inProgress }
      .sorted { $0.createdAt > $1.createdAt }

    if runningJobs.isEmpty && recentJobs.isEmpty {
      menu.addItem(disabledItem(title: "No Task Jobs"))
      return menu
    }

    for job in runningJobs {
      let item = NSMenuItem(
        title: "\(taskJobStatusPrefix(for: job.status)) \(job.ticket)", action: nil,
        keyEquivalent: "")
      menu.addItem(item)
      menu.setSubmenu(taskJobMenu(for: job), for: item)
    }

    if !runningJobs.isEmpty && !recentJobs.isEmpty {
      menu.addItem(.separator())
    }

    for job in recentJobs {
      let item = NSMenuItem(
        title: "\(taskJobStatusPrefix(for: job.status)) \(job.ticket)", action: nil,
        keyEquivalent: "")
      menu.addItem(item)
      menu.setSubmenu(taskJobMenu(for: job), for: item)
    }

    return menu
  }

  private func buildTaskCandidatesMenu(
    taskJobs: [CodexCoreCLIClient.TaskJob],
    taskCandidates: [CodexCoreCLIClient.TaskCandidate]
  ) -> NSMenu {
    let menu = NSMenu()

    if menuDataStore.data.isLoading {
      menu.addItem(disabledItem(title: "Loading..."))
      return menu
    }

    if taskCandidates.isEmpty {
      menu.addItem(disabledItem(title: "No Current Sprint Tasks"))
      return menu
    }

    let latestTaskJobByTicket = latestTaskJobsByTicket(taskJobs)
    let groupedCandidates = groupTaskCandidates(taskCandidates)

    for (index, group) in groupedCandidates.enumerated() {
      let repositoryItem = NSMenuItem(
        title: group.repository, action: #selector(openAgentURL(_:)), keyEquivalent: "")
      repositoryItem.target = self
      repositoryItem.representedObject = "https://github.com/\(group.repository)"
      repositoryItem.attributedTitle = NSAttributedString(
        string: group.repository,
        attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)]
      )
      menu.addItem(repositoryItem)

      for task in group.tasks {
        let markerPrefix = taskJobStatusPrefix(
          for: latestTaskJobByTicket[task.ticket]?.status, trailingSpace: true)
        let item = NSMenuItem(
          title: "\(markerPrefix)\(task.shortMenuTitle)", action: #selector(runAgentTask(_:)),
          keyEquivalent: "")
        item.target = self
        item.representedObject = task.ticket
        menu.addItem(item)
      }

      if index < groupedCandidates.count - 1 {
        menu.addItem(.separator())
      }
    }

    return menu
  }

  private func buildReviewMenu(
    reviewJobs: [CodexCoreCLIClient.ReviewJob],
    reviewPullRequests: [CodexCoreCLIClient.ReviewPullRequest]
  ) -> NSMenu {
    let reviewMenu = NSMenu()

    if menuDataStore.data.isLoading {
      reviewMenu.addItem(disabledItem(title: "Loading..."))
      return reviewMenu
    }

    if reviewPullRequests.isEmpty {
      reviewMenu.addItem(disabledItem(title: "No Open PRs"))
      return reviewMenu
    }

    let latestReviewJobByPullRequestURL = latestReviewJobsByPullRequestURL(reviewJobs)
    let groupedPullRequests = groupReviewPullRequests(reviewPullRequests)

    for (index, group) in groupedPullRequests.enumerated() {
      let repositoryItem = NSMenuItem(
        title: group.repository,
        action: #selector(openAgentURL(_:)),
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

    return reviewMenu
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

  private func latestTaskJobsByTicket(_ taskJobs: [CodexCoreCLIClient.TaskJob]) -> [String:
    CodexCoreCLIClient.TaskJob]
  {
    var jobsByTicket: [String: CodexCoreCLIClient.TaskJob] = [:]
    for job in taskJobs.sorted(by: { $0.createdAt > $1.createdAt }) {
      if jobsByTicket[job.ticket] == nil {
        jobsByTicket[job.ticket] = job
      }
    }
    return jobsByTicket
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

  private func groupTaskCandidates(
    _ taskCandidates: [CodexCoreCLIClient.TaskCandidate]
  ) -> [(repository: String, tasks: [CodexCoreCLIClient.TaskCandidate])] {
    var groupedTasks: [(repository: String, tasks: [CodexCoreCLIClient.TaskCandidate])] = []
    var groupedTaskIndexByRepository: [String: Int] = [:]

    for task in taskCandidates {
      if let existingIndex = groupedTaskIndexByRepository[task.repoFullName] {
        groupedTasks[existingIndex].tasks.append(task)
        continue
      }

      groupedTaskIndexByRepository[task.repoFullName] = groupedTasks.count
      groupedTasks.append((repository: task.repoFullName, tasks: [task]))
    }

    return groupedTasks
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

  private func taskJobMenu(for job: CodexCoreCLIClient.TaskJob) -> NSMenu {
    let taskMenu = NSMenu()
    taskMenu.addItem(disabledItem(title: "Status: \(taskJobStatusText(for: job.status))"))
    taskMenu.addItem(disabledItem(title: "Step: \(job.currentStep)"))
    taskMenu.addItem(.separator())

    let openTicketItem = NSMenuItem(
      title: "Open Ticket", action: #selector(openAgentURL(_:)), keyEquivalent: "")
    openTicketItem.target = self
    openTicketItem.representedObject = job.issueURL
    taskMenu.addItem(openTicketItem)

    if let prURL = job.prURL {
      let openPRItem = NSMenuItem(
        title: "Open PR", action: #selector(openAgentURL(_:)), keyEquivalent: "")
      openPRItem.target = self
      openPRItem.representedObject = prURL
      taskMenu.addItem(openPRItem)
    }

    let rerunItem = NSMenuItem(
      title: "Re-run Task", action: #selector(rerunCodexAgentTask(_:)), keyEquivalent: "")
    rerunItem.target = self
    rerunItem.representedObject = job.ticket
    taskMenu.addItem(rerunItem)
    return taskMenu
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

  private func taskJobStatusPrefix(
    for status: CodexCoreCLIClient.TaskJob.Status?,
    trailingSpace: Bool = false
  ) -> String {
    guard let status else {
      return ""
    }
    return taskJobStatusPrefix(for: status, trailingSpace: trailingSpace)
  }

  private func taskJobStatusText(for status: CodexCoreCLIClient.TaskJob.Status) -> String {
    switch status {
    case .completed:
      return "completed"
    case .failed:
      return "failed"
    case .inProgress:
      return "in_progress"
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
