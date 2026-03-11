import AppKit
import Foundation

extension AppDelegate {
    func rebuildMenu(_ menu: NSMenu) {
        let data = menuDataStore.data
        menu.removeAllItems()

        let openItem = NSMenuItem(title: "Codex", action: #selector(openCodexApp(_:)), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        addCodexAgentSection(to: menu)

        menu.addItem(.separator())

        let remoteHeader = NSMenuItem(title: "", action: #selector(noopHeader(_:)), keyEquivalent: "")
        remoteHeader.attributedTitle = NSAttributedString(
            string: "Remote",
            attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)]
        )
        remoteHeader.target = self
        remoteHeader.isEnabled = true
        menu.addItem(remoteHeader)

        switch remoteCLI.menuAction(remoteStatus: data.remoteStatus, isLoading: data.isLoading) {
        case .install:
            let install = NSMenuItem(title: "Install Remote…",
                                     action: #selector(installCodexRemote(_:)),
                                     keyEquivalent: "")
            install.target = self
            menu.addItem(install)
        case .start:
            let start = NSMenuItem(title: "Start",
                                   action: #selector(startCodexRemote(_:)),
                                   keyEquivalent: "")
            start.target = self
            menu.addItem(start)
        case .stop:
            let stop = NSMenuItem(title: "Stop",
                                  action: #selector(stopCodexRemote(_:)),
                                  keyEquivalent: "")
            stop.target = self
            menu.addItem(stop)
        }

        menu.addItem(.separator())

        let authHeader = NSMenuItem(title: "", action: #selector(noopHeader(_:)), keyEquivalent: "")
        authHeader.attributedTitle = NSAttributedString(
            string: "Profiles",
            attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)]
        )
        authHeader.target = self
        authHeader.isEnabled = true
        menu.addItem(authHeader)

        let authMenuProfiles = authCLI.menuProfiles(currentProfileName: data.currentProfileName,
                                                    profiles: data.profiles,
                                                    isLoading: data.isLoading)
        for profile in authMenuProfiles {
            let profileItem = NSMenuItem(title: displayProfileName(profile.normalizedName), action: nil, keyEquivalent: "")
            profileItem.state = profile.isCurrent ? .on : .off

            let profileMenu = NSMenu()
            for action in profile.actions {
                profileMenu.addItem(authProfileActionItem(for: action, profileName: profile.normalizedName))
            }

            menu.addItem(profileItem)
            menu.setSubmenu(profileMenu, for: profileItem)
        }

        let add = NSMenuItem(title: "Add", action: #selector(addProfileFromCurrent(_:)), keyEquivalent: "")
        add.target = self
        menu.addItem(add)

        menu.addItem(.separator())

        let sessionsItem = NSMenuItem(title: "Threads", action: nil, keyEquivalent: "")
        let sessionsMenu = NSMenu()
        if data.isLoading {
            let loadingItem = NSMenuItem(title: "Loading...", action: nil, keyEquivalent: "")
            loadingItem.isEnabled = false
            sessionsMenu.addItem(loadingItem)
        } else {
            switch data.sessionsStatus ?? .notInstalled {
            case .notInstalled:
                let missingItem = NSMenuItem(title: "Threads CLI not installed (codex-sessions)", action: nil, keyEquivalent: "")
                missingItem.isEnabled = false
                sessionsMenu.addItem(missingItem)
            case .ready:
                let autoRemoveHeader = NSMenuItem(title: "Auto-Remove", action: #selector(clearAutoRemoveSelection(_:)), keyEquivalent: "")
                autoRemoveHeader.target = self
                autoRemoveHeader.isEnabled = true
                sessionsMenu.addItem(autoRemoveHeader)

                sessionsMenu.addItem(autoRemoveDayMenuItem(days: 1))
                sessionsMenu.addItem(autoRemoveDayMenuItem(days: 3))
                sessionsMenu.addItem(autoRemoveDayMenuItem(days: 7))

                sessionsMenu.addItem(.separator())
            }
        }
        menu.addItem(sessionsItem)
        menu.setSubmenu(sessionsMenu, for: sessionsItem)

        menu.addItem(.separator())

        let help = NSMenuItem(title: "Help", action: #selector(openHelp(_:)), keyEquivalent: "")
        help.target = self
        menu.addItem(help)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func addCodexAgentSection(to menu: NSMenu) {
        let agentHeader = NSMenuItem(title: "", action: #selector(noopHeader(_:)), keyEquivalent: "")
        agentHeader.attributedTitle = NSAttributedString(
            string: "Agents",
            attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)]
        )
        agentHeader.target = self
        agentHeader.isEnabled = true
        menu.addItem(agentHeader)

        let createAgent = NSMenuItem(title: "Create",
                                     action: #selector(createCodexAgent(_:)),
                                     keyEquivalent: "")
        createAgent.target = self
        menu.addItem(createAgent)

        addAgentTaskGroup(title: "Running Tasks",
                          tasks: CodexAgentMockData.runningTasks,
                          to: menu) { [self] task in
            let taskMenu = baseAgentTaskMenu(for: task)
            let pauseOrResumeTitle = task.isPaused ? "Resume Task" : "Pause Task"
            taskMenu.addItem(agentTaskActionItem(title: pauseOrResumeTitle,
                                                 action: #selector(togglePauseCodexAgentTask(_:)),
                                                 ticket: task.ticket))
            taskMenu.addItem(agentTaskActionItem(title: "Delete Task",
                                                 action: #selector(deleteCodexAgentTask(_:)),
                                                 ticket: task.ticket))
            return taskMenu
        }

        addAgentTaskGroup(title: "Recent Tasks",
                          tasks: CodexAgentMockData.recentTasks,
                          to: menu) { [self] task in
            let taskMenu = baseAgentTaskMenu(for: task)
            taskMenu.addItem(agentTaskActionItem(title: "Re-run Task",
                                                 action: #selector(rerunCodexAgentTask(_:)),
                                                 ticket: task.ticket))
            return taskMenu
        }

        let settingsItem = NSMenuItem(title: "Settings…",
                                      action: #selector(openCodexAgentSettings(_:)),
                                      keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
    }

    private func addAgentTaskGroup(title: String,
                                   tasks: [CodexAgentMockTask],
                                   to menu: NSMenu,
                                   taskMenuBuilder: (CodexAgentMockTask) -> NSMenu) {
        let groupItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let groupMenu = NSMenu()

        if tasks.isEmpty {
            groupItem.isEnabled = false
        } else {
            for task in tasks {
                let taskItem = NSMenuItem(title: task.ticket, action: nil, keyEquivalent: "")
                groupMenu.addItem(taskItem)
                groupMenu.setSubmenu(taskMenuBuilder(task), for: taskItem)
            }
        }

        menu.addItem(groupItem)
        menu.setSubmenu(groupMenu, for: groupItem)
    }

    private func baseAgentTaskMenu(for task: CodexAgentMockTask) -> NSMenu {
        let taskMenu = NSMenu()

        let statusItem = NSMenuItem(title: "Status: \(task.status.rawValue)", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        taskMenu.addItem(statusItem)
        taskMenu.addItem(.separator())
        taskMenu.addItem(agentTaskActionItem(title: "View Task",
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

    private func authProfileActionItem(for action: CodexAuthCLIClient.MenuProfileAction,
                                       profileName: String) -> NSMenuItem {
        let item: NSMenuItem

        switch action {
        case .use:
            item = NSMenuItem(title: "Use",
                              action: #selector(useNamedProfile(_:)),
                              keyEquivalent: "")
        case .remove:
            item = NSMenuItem(title: "Remove",
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

    private func autoRemoveModeSubmenuItem(days: Int,
                                           mode: CodexSessionsCLIClient.AutoRemoveMode) -> NSMenuItem {
        let item = NSMenuItem(
            title: mode == .archive ? "Archive" : "Delete",
            action: #selector(setAutoRemoveSelection(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = "\(days):\(mode.rawValue)"
        item.state = (autoRemoveSettings.olderThanDays == days && autoRemoveSettings.mode == mode) ? .on : .off
        return item
    }
}
