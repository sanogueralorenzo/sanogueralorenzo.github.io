import AppKit
import Foundation
import Observation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let authCLI = CodexAuthCLIClient()
    let remoteCLI = CodexRemoteCLIClient()
    let sessionsCLI = CodexSessionsCLIClient()
    let menuDataStore = CodexMenuDataStore()
    var autoRemoveSettings = AutoRemoveSettings.load()
    let autoRemoveQueue = DispatchQueue(
        label: "io.github.sanogueralorenzo.codex-menubar.auto-remove",
        qos: .utility
    )
    var autoRemoveTimer: DispatchSourceTimer?
    let autoRemoveIntervalMinutes = 60
    var statusItem: NSStatusItem!
    private var isMenuOpen = false
    private var needsRenderAfterMenuClose = false

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

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = StatusBarIcon.codex()
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.title = ""

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        startAutoRemoveWatcher()
        observeMenuDataChanges()
        renderMenu()
        refreshUI()
    }

    func refreshTitle() {
        let profile = menuDataStore.data.currentProfileName
        let tooltip: String
        if let profile {
            tooltip = "Profiles (\(displayProfileName(profile)))"
        } else {
            tooltip = "Profiles"
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

    func refreshUI() {
        menuDataStore.refresh(authCLI: authCLI,
                              remoteCLI: remoteCLI,
                              sessionsCLI: sessionsCLI)
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

struct AutoRemoveSettings: Equatable {
    let olderThanDays: Int?
    let mode: CodexSessionsCLIClient.AutoRemoveMode?

    static let supportedDays = [1, 3, 7]
    static let none = AutoRemoveSettings(olderThanDays: nil, mode: nil)

    private static let selectionKey = "threads.autoRemove.selection"

    static func load(defaults: UserDefaults = .standard) -> AutoRemoveSettings {
        guard let selection = defaults.string(forKey: selectionKey) else {
            return .none
        }

        let components = selection.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        guard components.count == 2,
              let days = Int(components[0]),
              supportedDays.contains(days),
              let mode = CodexSessionsCLIClient.AutoRemoveMode(rawValue: String(components[1])) else {
            return .none
        }

        return AutoRemoveSettings(olderThanDays: days, mode: mode)
    }

    func save(defaults: UserDefaults = .standard) {
        guard let olderThanDays, let mode else {
            defaults.removeObject(forKey: Self.selectionKey)
            return
        }
        defaults.set("\(olderThanDays):\(mode.rawValue)", forKey: Self.selectionKey)
    }

    var isConfigured: Bool {
        olderThanDays != nil && mode != nil
    }

    func withSelection(days: Int, mode: CodexSessionsCLIClient.AutoRemoveMode) -> AutoRemoveSettings {
        AutoRemoveSettings(olderThanDays: days, mode: mode)
    }
}
