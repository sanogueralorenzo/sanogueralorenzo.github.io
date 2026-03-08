import AppKit
import Foundation
import Observation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let authCLI = CodexAuthCLIClient()
    let remoteCLI = CodexRemoteCLIClient()
    let sessionsCLI = CodexSessionsCLIClient()
    let skillsProvider = CodexSkillsProvider(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    let rateLimitsProvider = CodexRateLimitsProvider()
    let menuDataStore = CodexMenuDataStore()
    var statusItem: NSStatusItem!
    private var isMenuOpen = false
    private var needsRenderAfterMenuClose = false
    private let sessionTitleWatcherPreferenceKey = "codex.menubar.sessions.watch-thread-titles.enabled"

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try LaunchAgentInstaller.ensureLaunchAgentPlistExists()
        } catch {
            fputs("Warning: failed to configure auto-start: \(error)\n", stderr)
        }

        do {
            try authCLI.startWatcher()
        } catch {
            fputs("Warning: failed to start codex-auth watcher: \(error)\n", stderr)
        }

        if isSessionTitleWatcherPreferredEnabled() {
            let sessionsCLI = self.sessionsCLI
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                do {
                    try sessionsCLI.startTitleWatcher()
                } catch {
                    fputs("Warning: failed to start codex-sessions thread-title watcher: \(error)\n", stderr)
                }
                DispatchQueue.main.async {
                    self?.refreshUI()
                }
            }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = StatusBarIcon.codex()
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.title = ""

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        observeMenuDataChanges()
        renderMenu()
        refreshUI()
    }

    func refreshTitle() {
        let profile = menuDataStore.data.currentProfileName
        let tooltip: String
        if let profile {
            tooltip = "Codex Auth (\(displayProfileName(profile)))"
        } else {
            tooltip = "Codex Auth"
        }
        statusItem.button?.toolTip = tooltip
    }

    func displayProfileName(_ normalizedName: String) -> String {
        let withSpaces = normalizedName.replacingOccurrences(of: "-", with: " ")
        guard let first = withSpaces.first else {
            return withSpaces
        }
        return String(first).uppercased() + withSpaces.dropFirst()
    }

    func isSessionTitleWatcherPreferredEnabled() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: sessionTitleWatcherPreferenceKey) == nil {
            return true
        }
        return defaults.bool(forKey: sessionTitleWatcherPreferenceKey)
    }

    func setSessionTitleWatcherPreferredEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: sessionTitleWatcherPreferenceKey)
    }

    func refreshUI() {
        menuDataStore.refresh(authCLI: authCLI,
                              remoteCLI: remoteCLI,
                              sessionsCLI: sessionsCLI,
                              skillsProvider: skillsProvider,
                              rateLimitsProvider: rateLimitsProvider)
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        refreshUI()
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        if needsRenderAfterMenuClose {
            needsRenderAfterMenuClose = false
            renderMenu()
        }
    }

    func showError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)

        let message: String
        if let localized = error as? LocalizedError, let text = localized.errorDescription {
            message = text
        } else {
            message = String(describing: error)
        }

        let alert = NSAlert()
        alert.messageText = "Codex Menu"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func renderMenu() {
        refreshTitle()
        if let menu = statusItem.menu {
            rebuildMenu(menu)
        }
    }

    private func observeMenuDataChanges() {
        withObservationTracking {
            _ = menuDataStore.data
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                if self.isMenuOpen {
                    self.needsRenderAfterMenuClose = true
                } else {
                    self.renderMenu()
                }
                self.observeMenuDataChanges()
            }
        }
    }
}
